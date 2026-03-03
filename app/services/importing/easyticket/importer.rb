require "digest"
require "set"

module Importing
  module Easyticket
    class Importer
      RUN_STALE_AFTER = 1.hour
      RUN_HEARTBEAT_STALE_AFTER = 2.minutes
      PROGRESS_FLUSH_EVERY_N_CHANGES = 25
      PROGRESS_FLUSH_AFTER_SECONDS = 2
      FILTERED_OUT_CITIES_LIMIT = 500

      def initialize(
        import_source:,
        dump_fetcher: DumpFetcher.new,
        detail_fetcher: DetailFetcher.new,
        run_metadata: {},
        logger: Rails.logger
      )
        @import_source = import_source
        @dump_fetcher = dump_fetcher
        @detail_fetcher = detail_fetcher
        @run_metadata = run_metadata
        @logger = logger
      end

      def call
        run = nil
        import_source.with_lock do
          fail_stale_runs!
          active_run = active_running_run
          if active_run.present?
            logger.info("[EasyticketImporter] skipped because run_id=#{active_run.id} is already running")
            return active_run
          end

          run = import_source.import_runs.create!(
            status: "running",
            source_type: import_source.source_type,
            started_at: Time.current,
            metadata: normalized_metadata(run_metadata)
          )
          broadcast_runs_update!
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
        events = dump_fetcher.fetch_events
        fetched_count = events.size
        return run.reload if run_canceled?(run)

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

        events.each do |dump_payload|
          if run_canceled?(run)
            canceled = true
            break
          end

          if stop_requested?(run)
            canceled = true
            break
          end

          progress_changed = false
          event_id = dump_payload["event_id"].to_s.strip
          next if event_id.blank?

          unless matcher.match?(dump_payload)
            add_filtered_out_city!(filtered_out_cities, dump_payload["loc_city"])
            next
          end

          filtered_count += 1
          progress_changed = true
          source_payload_hash = build_source_payload_hash(dump_payload)
          existing_record = find_existing_import_event(event_id, dump_payload)
          if unchanged_dump_payload?(existing_record, source_payload_hash)
            mark_existing_event_as_seen!(
              record: existing_record,
              dump_payload: dump_payload,
              seen_at: run_started_at
            )
            imported_count += 1
            next
          end

          detail_payload = detail_fetcher.fetch(event_id)

          projection = PayloadProjection.new(
            dump_payload: dump_payload,
            detail_payload: detail_payload
          )
          attributes = projection.to_attributes
          if attributes.nil?
            failed_count += 1
            progress_changed = true
            next
          end

          upsert_import_event!(
            attributes: attributes,
            dump_payload: dump_payload,
            detail_payload: detail_payload,
            seen_at: run_started_at
          )
          imported_count += 1
          upserted_count += 1
          progress_changed = true
        rescue StandardError => e
          failed_count += 1
          progress_changed = true
          logger.error("[EasyticketImporter] event_id=#{event_id} failed: #{e.class}: #{e.message}")
          create_import_run_error!(
            run: run,
            error: e,
            external_event_id: event_id,
            payload: dump_payload
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

      attr_reader :import_source, :dump_fetcher, :detail_fetcher, :run_metadata, :logger

      def upsert_import_event!(attributes:, dump_payload:, detail_payload:, seen_at:)
        record = EasyticketImportEvent.find_or_initialize_by(
          import_source_id: import_source.id,
          external_event_id: attributes[:external_event_id],
          concert_date: attributes[:concert_date]
        )

        record.assign_attributes(
          attributes.merge(
            dump_payload: dump_payload,
            detail_payload: detail_payload,
            is_active: true,
            first_seen_at: record.first_seen_at || seen_at,
            last_seen_at: seen_at
          )
        )
        record.save!
      end

      def deactivate_stale_events!(seen_at:)
        import_source
          .easyticket_import_events
          .where("last_seen_at < ? OR last_seen_at IS NULL", seen_at)
          .update_all(is_active: false)
      end

      def active_running_run
        import_source.import_runs.where(status: "running").order(started_at: :desc).first
      end

      def fail_stale_runs!
        stale_runs =
          import_source
            .import_runs
            .where(status: "running")
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

          next unless stale_run_stop_requested?(stale_run)

          stale_run.update_columns(
            status: "canceled",
            finished_at: Time.current,
            updated_at: Time.current
          )
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
        logger.error("[EasyticketImporter] failed to broadcast run update: #{e.class}: #{e.message}")
      end

      def find_existing_import_event(event_id, dump_payload)
        concert_date = parse_concert_date_from_dump(dump_payload)
        return nil if concert_date.nil?

        import_source.easyticket_import_events.find_by(
          external_event_id: event_id,
          concert_date: concert_date
        )
      end

      def parse_concert_date_from_dump(dump_payload)
        raw_date = dump_payload["date"].to_s.strip
        return nil if raw_date.blank?

        Date.parse(raw_date)
      rescue ArgumentError
        nil
      end

      def build_source_payload_hash(dump_payload)
        Digest::SHA256.hexdigest(dump_payload.to_json)
      end

      def unchanged_dump_payload?(existing_record, source_payload_hash)
        existing_record.present? && existing_record.source_payload_hash == source_payload_hash
      end

      def mark_existing_event_as_seen!(record:, dump_payload:, seen_at:)
        record.update_columns(
          dump_payload: dump_payload,
          is_active: true,
          last_seen_at: seen_at,
          updated_at: Time.current
        )
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
        logger.error("[EasyticketImporter] failed to persist import run error: #{create_error.class}: #{create_error.message}")
      end

      def add_filtered_out_city!(cities_set, city_value)
        return if cities_set.size >= FILTERED_OUT_CITIES_LIMIT

        city = city_value.to_s.strip
        return if city.blank?

        cities_set << city
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
