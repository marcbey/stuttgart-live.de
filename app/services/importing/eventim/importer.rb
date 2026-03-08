require "set"

module Importing
  module Eventim
    class Importer
      RUN_STALE_AFTER = 1.hour
      RUN_HEARTBEAT_STALE_AFTER = 2.minutes
      PROGRESS_FLUSH_EVERY_N_CHANGES = 1000
      PROGRESS_FLUSH_AFTER_SECONDS = 2
      FILTERED_OUT_CITIES_LIMIT = 500

      def initialize(import_source:, feed_fetcher: FeedFetcher.new, preexisting_run_id: nil, run_metadata: {}, logger: Rails.logger)
        @import_source = import_source
        @feed_fetcher = feed_fetcher
        @preexisting_run_id = preexisting_run_id
        @run_metadata = run_metadata
        @logger = logger
      end

      def call
        run = nil
        import_source.with_lock do
          fail_stale_runs!
          run = claim_preexisting_run!
          active_run = active_running_run if run.nil?
          if active_run.present?
            logger.info("[EventimImporter] skipped because run_id=#{active_run.id} is already running")
            return active_run
          end

          if run.nil?
            run = import_source.import_runs.create!(
              status: "running",
              source_type: import_source.source_type,
              started_at: Time.current,
              metadata: normalized_metadata(run_metadata)
            )
            broadcast_runs_update!
          end
        end

        run_started_at = run.started_at
        fetched_count = 0
        filtered_count = 0
        imported_count = 0
        upserted_count = 0
        failed_count = 0
        canceled = false
        filtered_out_cities = Set.new

        location_whitelist = import_source.configured_location_whitelist
        matcher = LocationMatcher.new(location_whitelist)
        persist_progress!(
          run,
          fetched_count: fetched_count,
          filtered_count: filtered_count,
          imported_count: imported_count,
          upserted_count: upserted_count,
          failed_count: failed_count
        )

        changed_since_flush = 0
        last_flush_at = Time.current

        process_feed_payload = lambda do |feed_payload|
          if run_canceled?(run) || stop_requested?(run)
            canceled = true
            throw :stop_import
          end

          progress_changed = false

          fetched_count += 1
          progress_changed = true

          unless matcher.match?(feed_payload)
            add_filtered_out_city!(filtered_out_cities, filtered_out_city_from_feed(feed_payload))
            next
          end

          filtered_count += 1

          projection = PayloadProjection.new(feed_payload: feed_payload)
          attributes = projection.to_attributes
          if attributes.nil?
            failed_count += 1
            next
          end

          existing_record = find_existing_import_event(attributes)
          if unchanged_feed_payload?(existing_record, attributes[:source_payload_hash])
            sync_import_event_images!(
              record: existing_record,
              source: "eventim",
              candidates: projection.image_candidates
            )
            mark_existing_event_as_seen!(
              record: existing_record,
              feed_payload: feed_payload,
              attributes: attributes,
              seen_at: run_started_at
            )
            imported_count += 1
            next
          end

          upsert_import_event!(
            attributes: attributes,
            feed_payload: feed_payload,
            image_candidates: projection.image_candidates,
            seen_at: run_started_at
          )
          imported_count += 1
          upserted_count += 1
        rescue StandardError => e
          failed_count += 1
          progress_changed = true
          logger.error("[EventimImporter] failed: #{e.class}: #{e.message}")
          create_import_run_error!(
            run: run,
            error: e,
            external_event_id: external_event_id_from_feed(feed_payload),
            payload: feed_payload
          )
        ensure
          next unless progress_changed

          changed_since_flush += 1
          next unless should_flush_progress?(changed_since_flush, last_flush_at)

          persist_progress!(
            run,
            fetched_count: fetched_count,
            filtered_count: filtered_count,
            imported_count: imported_count,
            upserted_count: upserted_count,
            failed_count: failed_count
          )
          changed_since_flush = 0
          last_flush_at = Time.current
        end

        catch(:stop_import) do
          streamed_rows = false
          returned_rows = feed_fetcher.fetch_events do |feed_payload|
            streamed_rows = true
            process_feed_payload.call(feed_payload)
          end

          next if streamed_rows

          Array(returned_rows).each do |feed_payload|
            process_feed_payload.call(feed_payload)
          end
        end

        persist_progress!(
          run,
          fetched_count: fetched_count,
          filtered_count: filtered_count,
          imported_count: imported_count,
          upserted_count: upserted_count,
          failed_count: failed_count
        )
        canceled ||= run_canceled?(run)

        if canceled
          run.update!(
            status: "canceled",
            finished_at: Time.current,
            fetched_count: fetched_count,
            filtered_count: filtered_count,
            imported_count: imported_count,
            upserted_count: upserted_count,
            failed_count: failed_count,
            metadata: run_completion_metadata(
              run: run,
              location_whitelist: location_whitelist,
              filtered_out_cities: filtered_out_cities
            )
          )
          broadcast_runs_update!
          return run
        end

        return run.reload if run_canceled?(run)

        deactivate_stale_events!(seen_at: run_started_at)

        run.update!(
          status: "succeeded",
          finished_at: Time.current,
          fetched_count: fetched_count,
          filtered_count: filtered_count,
          imported_count: imported_count,
          upserted_count: upserted_count,
          failed_count: failed_count,
          metadata: run_completion_metadata(
            run: run,
            location_whitelist: location_whitelist,
            filtered_out_cities: filtered_out_cities
          )
        )
        broadcast_runs_update!

        run
      rescue StandardError => e
        return run.reload if run&.persisted? && run_canceled?(run)

        run&.update!(
          status: "failed",
          finished_at: Time.current,
          fetched_count: fetched_count || 0,
          filtered_count: filtered_count || 0,
          imported_count: imported_count || 0,
          upserted_count: upserted_count || 0,
          failed_count: failed_count || 0,
          error_message: e.message,
          metadata: run_completion_metadata(
            run: run,
            location_whitelist: location_whitelist,
            filtered_out_cities: filtered_out_cities
          )
        )
        create_import_run_error!(
          run: run,
          error: e,
          payload: {}
        )
        broadcast_runs_update!
        raise
      end

      private

      attr_reader :import_source, :feed_fetcher, :run_metadata, :logger

      def upsert_import_event!(attributes:, feed_payload:, image_candidates:, seen_at:)
        record = EventimImportEvent.find_or_initialize_by(
          import_source_id: import_source.id,
          external_event_id: attributes[:external_event_id],
          concert_date: attributes[:concert_date]
        )

        record.assign_attributes(
          attributes.merge(
            dump_payload: feed_payload,
            detail_payload: {},
            is_active: true,
            first_seen_at: record.first_seen_at || seen_at,
            last_seen_at: seen_at
          )
        )
        record.save!
        sync_import_event_images!(
          record: record,
          source: "eventim",
          candidates: image_candidates
        )
      end

      def deactivate_stale_events!(seen_at:)
        import_source
          .eventim_import_events
          .where("last_seen_at < ? OR last_seen_at IS NULL", seen_at)
          .update_all(is_active: false)
      end

      def active_running_run
        import_source.import_runs.where(source_type: "eventim", status: "running").order(started_at: :desc).first
      end

      def claim_preexisting_run!
        return nil if @preexisting_run_id.blank?

        run = import_source.import_runs.lock.find_by(id: @preexisting_run_id, source_type: "eventim")
        return nil unless run.present?
        return run if run.status == "running"
        return nil unless run.status == "queued"

        run.update!(
          status: "running",
          metadata: normalized_metadata(run.metadata).merge(normalized_metadata(run_metadata))
        )
        broadcast_runs_update!
        run
      end

      def fail_stale_runs!
        stale_runs =
          import_source
            .import_runs
            .where(source_type: "eventim", status: "running")
            .where("started_at < ? OR updated_at < ?", RUN_STALE_AFTER.ago, RUN_HEARTBEAT_STALE_AFTER.ago)
            .to_a

        return if stale_runs.empty?

        stale_runs.each do |stale_run|
          if stale_run.started_at < RUN_STALE_AFTER.ago
            stale_run.update_columns(
              status: "failed",
              finished_at: Time.current,
              error_message: "Run automatically marked failed after timeout (#{RUN_STALE_AFTER.inspect})",
              updated_at: Time.current
            )
            next
          end

          if stale_run_stop_requested?(stale_run)
            stale_run.update_columns(
              status: "canceled",
              finished_at: Time.current,
              updated_at: Time.current
            )
          else
            stale_run.update_columns(
              status: "failed",
              finished_at: Time.current,
              error_message: "Run automatically marked failed after heartbeat timeout (#{RUN_HEARTBEAT_STALE_AFTER.inspect})",
              updated_at: Time.current
            )
          end
        end
        broadcast_runs_update!
      end

      def should_flush_progress?(changed_since_flush, last_flush_at)
        return true if changed_since_flush >= PROGRESS_FLUSH_EVERY_N_CHANGES

        (Time.current - last_flush_at) >= PROGRESS_FLUSH_AFTER_SECONDS
      end

      def persist_progress!(run, fetched_count:, filtered_count:, imported_count:, upserted_count:, failed_count:)
        return unless run_running?(run)

        run.update_columns(
          fetched_count: fetched_count,
          filtered_count: filtered_count,
          imported_count: imported_count,
          upserted_count: upserted_count,
          failed_count: failed_count,
          updated_at: Time.current
        )
        broadcast_runs_update!
      end

      def stop_requested?(run)
        ActiveModel::Type::Boolean.new.cast(normalized_metadata(run.reload.metadata)["stop_requested"])
      end

      def run_running?(run)
        run.reload.status == "running"
      end

      def run_canceled?(run)
        run.reload.status == "canceled"
      end

      def normalized_metadata(metadata)
        return {} unless metadata.is_a?(Hash)

        metadata.deep_stringify_keys
      end

      def stale_run_stop_requested?(run)
        ActiveModel::Type::Boolean.new.cast(normalized_metadata(run.metadata)["stop_requested"])
      end

      def broadcast_runs_update!
        Backend::ImportRunsBroadcaster.broadcast!
      rescue StandardError => e
        logger.error("[EventimImporter] failed to broadcast run update: #{e.class}: #{e.message}")
      end

      def find_existing_import_event(attributes)
        import_source.eventim_import_events.find_by(
          external_event_id: attributes[:external_event_id],
          concert_date: attributes[:concert_date]
        )
      end

      def unchanged_feed_payload?(existing_record, source_payload_hash)
        existing_record.present? && existing_record.source_payload_hash == source_payload_hash
      end

      def mark_existing_event_as_seen!(record:, feed_payload:, attributes:, seen_at:)
        promoter_id = attributes[:promoter_id].to_s.strip.presence || record.promoter_id

        record.update_columns(
          dump_payload: feed_payload,
          promoter_id: promoter_id,
          is_active: true,
          last_seen_at: seen_at,
          updated_at: Time.current
        )
      end

      def sync_import_event_images!(record:, source:, candidates:)
        normalized_candidates = normalize_image_candidates(candidates, source: source)
        existing_by_key = record.import_event_images.index_by do |image|
          image_key(source: image.source, image_type: image.image_type, image_url: image.image_url)
        end

        normalized_candidates.each_with_index do |candidate, index|
          key = image_key(
            source: candidate[:source],
            image_type: candidate[:image_type],
            image_url: candidate[:image_url]
          )
          image = existing_by_key.delete(key) || record.import_event_images.new
          image.assign_attributes(
            source: candidate[:source],
            image_type: candidate[:image_type],
            image_url: candidate[:image_url],
            role: candidate[:role],
            aspect_hint: candidate[:aspect_hint],
            position: index
          )
          image.save! if image.new_record? || image.changed?
        end

        existing_by_key.each_value(&:destroy!)
      end

      def normalize_image_candidates(candidates, source:)
        seen = Set.new

        Array(candidates).filter_map do |candidate|
          row = candidate.respond_to?(:to_h) ? candidate.to_h : {}
          image_url = ImportEventImage.normalize_image_url(row[:image_url] || row["image_url"])
          next if image_url.blank?

          image_type = (row[:image_type] || row["image_type"]).to_s.strip.presence || "image"
          normalized_source = source.to_s
          key = image_key(source: normalized_source, image_type: image_type, image_url: image_url)
          next if seen.include?(key)

          seen << key
          {
            source: normalized_source,
            image_type: image_type,
            image_url: image_url,
            role: (row[:role] || row["role"]).to_s.strip.presence || ImportEventImage.derive_role(source: normalized_source, image_type: image_type),
            aspect_hint: (row[:aspect_hint] || row["aspect_hint"]).to_s.strip.presence || ImportEventImage.derive_aspect_hint(url: image_url, image_type: image_type)
          }
        end
      end

      def image_key(source:, image_type:, image_url:)
        [
          source.to_s.strip.downcase,
          image_type.to_s.strip,
          image_url.to_s.strip.downcase
        ]
      end

      def external_event_id_from_feed(feed_payload)
        hash = feed_payload.is_a?(Hash) ? feed_payload.deep_stringify_keys : {}
        PayloadProjection::EVENT_ID_KEYS.each do |key|
          value = hash[key].to_s.strip
          return value if value.present?
        end

        nil
      end

      def create_import_run_error!(run:, error:, external_event_id: nil, payload: {})
        return unless run&.persisted?

        run.import_run_errors.create!(
          source_type: run.source_type,
          external_event_id: external_event_id,
          error_class: error.class.to_s,
          message: error.message.to_s.presence || error.class.to_s,
          payload: payload.is_a?(Hash) ? payload : {}
        )
      rescue StandardError => create_error
        logger.error("[EventimImporter] failed to persist import run error: #{create_error.class}: #{create_error.message}")
      end

      def add_filtered_out_city!(cities_set, city_value)
        return if cities_set.size >= FILTERED_OUT_CITIES_LIMIT

        city = city_value.to_s.strip
        return if city.blank?

        cities_set << city
      end

      def filtered_out_city_from_feed(feed_payload)
        hash = feed_payload.is_a?(Hash) ? feed_payload.deep_stringify_keys : {}
        keys = Importing::Eventim::LocationMatcher::CITY_KEYS

        keys.each do |key|
          value = hash[key].to_s.strip
          return value if value.present?
        end

        ""
      end

      def run_completion_metadata(run:, location_whitelist:, filtered_out_cities:)
        normalized_metadata(run.metadata).merge(
          "location_whitelist" => Array(location_whitelist),
          "filtered_out_cities" => filtered_out_cities.to_a.sort
        )
      end
    end
  end
end
