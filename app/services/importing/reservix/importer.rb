require "digest"
require "set"

module Importing
  module Reservix
    class Importer
      RUN_STALE_AFTER = 1.hour
      RUN_HEARTBEAT_STALE_AFTER = 2.minutes
      PROGRESS_FLUSH_EVERY_N_CHANGES = 50
      PROGRESS_FLUSH_AFTER_SECONDS = 2
      FILTERED_OUT_CITIES_LIMIT = 500
      CHECKPOINT_OVERLAP = 5.minutes

      def initialize(import_source:, event_fetcher: EventFetcher.new, preexisting_run_id: nil, run_metadata: {}, logger: Rails.logger)
        @import_source = import_source
        @event_fetcher = event_fetcher
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
            logger.info("[ReservixImporter] skipped because run_id=#{active_run.id} is already running")
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
        checkpoint = load_checkpoint
        checkpoint_tracker = checkpoint_tracker_for(checkpoint)

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

        catch(:stop_import) do
          event_fetcher.fetch_pages(lastupdate: checkpoint_query_value(checkpoint)) do |events, server_time:, **_page_context|
            advance_checkpoint_tracker!(checkpoint_tracker, modified_at: server_time)

            events.each do |event_payload|
              if run_canceled?(run) || stop_requested?(run)
                canceled = true
                throw :stop_import
              end

              progress_changed = false
              projection = PayloadProjection.new(event_payload: event_payload)
              modified_at = projection.modified_at
              external_event_id = event_payload["id"].to_s.strip

              advance_checkpoint_tracker!(
                checkpoint_tracker,
                modified_at: modified_at,
                event_id: external_event_id
              )

              fetched_count += 1
              progress_changed = true

              if already_processed_for_checkpoint?(checkpoint, modified_at: modified_at, event_id: external_event_id)
                next
              end

              unless matcher.match?(event_payload)
                add_filtered_out_city!(filtered_out_cities, filtered_out_city_from_payload(event_payload))
                next
              end

              unless projection.bookable?
                if deactivate_existing_import_event!(event_payload: event_payload, seen_at: run_started_at)
                  upserted_count += 1
                  progress_changed = true
                end
                next
              end

              filtered_count += 1

              attributes = projection.to_attributes
              if attributes.nil?
                failed_count += 1
                next
              end

              existing_record = find_existing_import_event(attributes[:external_event_id])
              if unchanged_payload?(existing_record, attributes[:source_payload_hash])
                sync_import_event_images!(
                  record: existing_record,
                  source: "reservix",
                  candidates: projection.image_candidates
                )
                mark_existing_event_as_seen!(
                  record: existing_record,
                  event_payload: event_payload,
                  attributes: attributes,
                  seen_at: run_started_at
                )
                imported_count += 1
                next
              end

              upsert_import_event!(
                attributes: attributes,
                event_payload: event_payload,
                image_candidates: projection.image_candidates,
                seen_at: run_started_at
              )
              imported_count += 1
              upserted_count += 1
            rescue StandardError => e
              failed_count += 1
              progress_changed = true
              logger.error("[ReservixImporter] event_id=#{external_event_id} failed: #{e.class}: #{e.message}")
              create_import_run_error!(
                run: run,
                error: e,
                external_event_id: external_event_id,
                payload: event_payload
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
              filtered_out_cities: filtered_out_cities,
              checkpoint_tracker: checkpoint_tracker
            )
          )
          broadcast_runs_update!
          return run
        end

        return run.reload if run_canceled?(run)

        persist_checkpoint!(checkpoint_tracker)

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
            filtered_out_cities: filtered_out_cities,
            checkpoint_tracker: checkpoint_tracker
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
            filtered_out_cities: filtered_out_cities,
            checkpoint_tracker: checkpoint_tracker
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

      attr_reader :import_source, :event_fetcher, :run_metadata, :logger

      def upsert_import_event!(attributes:, event_payload:, image_candidates:, seen_at:)
        record = find_existing_import_event(attributes[:external_event_id]) || import_source.reservix_import_events.new

        record.assign_attributes(
          attributes.merge(
            dump_payload: event_payload,
            detail_payload: {},
            is_active: true,
            first_seen_at: record.first_seen_at || seen_at,
            last_seen_at: seen_at
          )
        )
        record.save!
        sync_import_event_images!(
          record: record,
          source: "reservix",
          candidates: image_candidates
        )
      end

      def active_running_run
        import_source.import_runs.where(source_type: "reservix", status: "running").order(started_at: :desc).first
      end

      def claim_preexisting_run!
        return nil if @preexisting_run_id.blank?

        run = import_source.import_runs.lock.find_by(id: @preexisting_run_id, source_type: "reservix")
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
            .where(source_type: "reservix", status: "running")
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
        logger.error("[ReservixImporter] failed to broadcast run update: #{e.class}: #{e.message}")
      end

      def find_existing_import_event(external_event_id)
        import_source.reservix_import_events.find_by(external_event_id: external_event_id)
      end

      def unchanged_payload?(existing_record, source_payload_hash)
        existing_record.present? && existing_record.source_payload_hash == source_payload_hash
      end

      def mark_existing_event_as_seen!(record:, event_payload:, attributes:, seen_at:)
        record.update_columns(
          concert_date: attributes[:concert_date],
          concert_date_label: attributes[:concert_date_label],
          city: attributes[:city],
          venue_name: attributes[:venue_name],
          venue_label: attributes[:venue_label],
          title: attributes[:title],
          artist_name: attributes[:artist_name],
          min_price: attributes[:min_price],
          max_price: attributes[:max_price],
          ticket_url: attributes[:ticket_url],
          dump_payload: event_payload,
          is_active: true,
          last_seen_at: seen_at,
          updated_at: Time.current
        )
      end

      def deactivate_existing_import_event!(event_payload:, seen_at:)
        external_event_id = event_payload["id"].to_s.strip
        return false if external_event_id.blank?

        record = find_existing_import_event(external_event_id)
        return false unless record.present?

        source_payload_hash = Digest::SHA256.hexdigest((event_payload || {}).to_json)
        changed = !record.is_active? || record.source_payload_hash != source_payload_hash

        record.update_columns(
          dump_payload: event_payload,
          source_payload_hash: source_payload_hash,
          is_active: false,
          last_seen_at: seen_at,
          updated_at: Time.current
        )

        changed
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
        logger.error("[ReservixImporter] failed to persist import run error: #{create_error.class}: #{create_error.message}")
      end

      def add_filtered_out_city!(cities_set, city_value)
        return if cities_set.size >= FILTERED_OUT_CITIES_LIMIT

        city = city_value.to_s.strip
        return if city.blank?

        cities_set << city
      end

      def filtered_out_city_from_payload(event_payload)
        payload = event_payload.is_a?(Hash) ? event_payload.deep_stringify_keys : {}
        references = payload["references"].is_a?(Hash) ? payload["references"].deep_stringify_keys : {}
        venue = Array(references["venue"]).find { |entry| entry.is_a?(Hash) }&.deep_stringify_keys || {}

        venue["city"].to_s.strip
      end

      def load_checkpoint
        raw_checkpoint = import_source.import_source_config&.reservix_checkpoint || {}
        {
          modified_at: parse_checkpoint_time(raw_checkpoint["lastupdate"]),
          last_processed_event_id: raw_checkpoint["last_processed_event_id"].to_s.strip
        }
      end

      def checkpoint_query_value(checkpoint)
        modified_at = checkpoint[:modified_at]
        return nil if modified_at.nil?

        [ modified_at - CHECKPOINT_OVERLAP, Time.zone.at(0) ].max.strftime("%Y-%m-%d %H:%M:%S")
      end

      def parse_checkpoint_time(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        Time.zone.parse(raw)
      rescue ArgumentError
        nil
      end

      def already_processed_for_checkpoint?(checkpoint, modified_at:, event_id:)
        checkpoint_time = checkpoint[:modified_at]
        return false if checkpoint_time.nil? || modified_at.nil?

        if modified_at < checkpoint_time
          true
        elsif modified_at > checkpoint_time
          false
        else
          event_id_comparable_value(event_id) <= event_id_comparable_value(checkpoint[:last_processed_event_id])
        end
      end

      def checkpoint_tracker_for(checkpoint)
        {
          modified_at: checkpoint[:modified_at],
          last_processed_event_id: checkpoint[:last_processed_event_id].to_s.strip
        }
      end

      def advance_checkpoint_tracker!(tracker, modified_at:, event_id: nil)
        return if modified_at.nil?

        current_modified_at = tracker[:modified_at]
        normalized_event_id = event_id.to_s.strip

        if current_modified_at.nil? || modified_at > current_modified_at
          tracker[:modified_at] = modified_at
          tracker[:last_processed_event_id] = normalized_event_id
        elsif modified_at == current_modified_at && normalized_event_id.present? &&
            event_id_comparable_value(normalized_event_id) > event_id_comparable_value(tracker[:last_processed_event_id])
          tracker[:last_processed_event_id] = normalized_event_id
        end
      end

      def persist_checkpoint!(checkpoint_tracker)
        modified_at = checkpoint_tracker[:modified_at]
        return if modified_at.nil?

        config = import_source.import_source_config || import_source.build_import_source_config
        config.reservix_checkpoint = {
          "lastupdate" => modified_at.iso8601,
          "last_processed_event_id" => checkpoint_tracker[:last_processed_event_id].to_s.strip
        }
        config.save!
      end

      def run_completion_metadata(run:, location_whitelist:, filtered_out_cities:, checkpoint_tracker:)
        metadata = normalized_metadata(run.metadata).merge(
          "location_whitelist" => Array(location_whitelist),
          "filtered_out_cities" => filtered_out_cities.to_a.sort
        )

        checkpoint_value = checkpoint_metadata(checkpoint_tracker)
        metadata["reservix_checkpoint"] = checkpoint_value if checkpoint_value.present?
        metadata
      end

      def checkpoint_metadata(checkpoint_tracker)
        modified_at = checkpoint_tracker[:modified_at]
        return {} if modified_at.nil?

        {
          "lastupdate" => modified_at.iso8601,
          "last_processed_event_id" => checkpoint_tracker[:last_processed_event_id].to_s.strip
        }
      end

      def event_id_comparable_value(value)
        raw = value.to_s.strip
        return -1 if raw.blank?

        Integer(raw, exception: false) || raw
      end
    end
  end
end
