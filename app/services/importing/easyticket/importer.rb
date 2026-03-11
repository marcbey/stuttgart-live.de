require "digest"
require "json"
require "set"

module Importing
  module Easyticket
    class Importer
      include Importing::ImporterExecutionSupport
      include Importing::ImporterRunSupport

      RUN_STALE_AFTER = 1.hour
      RUN_HEARTBEAT_STALE_AFTER = 2.minutes
      PROGRESS_FLUSH_EVERY_N_CHANGES = 25
      PROGRESS_FLUSH_AFTER_SECONDS = 2
      FILTERED_OUT_CITIES_LIMIT = 500

      def initialize(
        import_source:,
        dump_fetcher: DumpFetcher.new,
        detail_fetcher: DetailFetcher.new,
        preexisting_run_id: nil,
        run_metadata: {},
        logger: Rails.logger
      )
        @import_source = import_source
        @dump_fetcher = dump_fetcher
        @detail_fetcher = detail_fetcher
        @preexisting_run_id = preexisting_run_id
        @run_metadata = run_metadata
        @logger = logger
      end

      def call
        prepared_run = prepare_import_run!
        return prepared_run.run unless prepared_run.process

        run = prepared_run.run
        state = initial_run_state(run:)
        matcher = LocationMatcher.new(state[:location_whitelist])
        events = dump_fetcher.fetch_events
        state[:fetched_count] = events.size
        return run.reload if run_canceled?(run)

        persist_progress_from_state!(run, state)

        changed_since_flush = 0
        last_flush_at = Time.current

        events.each do |dump_payload|
          if run_canceled?(run)
            state[:canceled] = true
            break
          end

          if stop_requested?(run)
            state[:canceled] = true
            break
          end

          progress_changed = false
          event_id = dump_payload["event_id"].to_s.strip
          next if event_id.blank?

          unless matcher.match?(dump_payload)
            add_filtered_out_city!(state[:filtered_out_cities], filtered_out_location_label(dump_payload))
            next
          end

          state[:filtered_count] += 1
          progress_changed = true
          source_payload_hash = build_source_payload_hash(dump_payload)
          existing_record = find_existing_import_event(event_id, dump_payload)
          projection = PayloadProjection.new(
            dump_payload: dump_payload,
            detail_payload: existing_record&.detail_payload || {}
          )
          attributes = projection.to_attributes
          if attributes.nil?
            state[:failed_count] += 1
            progress_changed = true
            next
          end

          detail_payload = build_detail_payload(event_id, dump_payload)

          projection = PayloadProjection.new(
            dump_payload: dump_payload,
            detail_payload: detail_payload
          )
          attributes = projection.to_attributes
          if attributes.nil?
            state[:failed_count] += 1
            progress_changed = true
            next
          end

          if unchanged_payloads?(existing_record, source_payload_hash, detail_payload)
            Importing::ImportEventImagesSync.call(
              owner: existing_record,
              source: "easyticket",
              candidates: projection.image_candidates
            )
            mark_existing_event_as_seen!(
              record: existing_record,
              dump_payload: dump_payload,
              detail_payload: detail_payload,
              attributes: attributes,
              seen_at: state[:run_started_at]
            )
            state[:imported_count] += 1
            next
          end

          upsert_import_event!(
            attributes: attributes,
            dump_payload: dump_payload,
            detail_payload: detail_payload,
            image_candidates: projection.image_candidates,
            seen_at: state[:run_started_at]
          )
          state[:imported_count] += 1
          state[:upserted_count] += 1
          progress_changed = true
        rescue StandardError => e
          state[:failed_count] += 1
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

          persist_progress_from_state!(run, state)
          changed_since_flush = 0
          last_flush_at = Time.current
        end

        persist_progress_from_state!(run, state)
        state[:canceled] ||= run_canceled?(run)

        if state[:canceled]
          return finalize_canceled_run!(
            run,
            state,
            metadata: run_completion_metadata(
              run: run,
              location_whitelist: state[:location_whitelist],
              filtered_out_cities: state[:filtered_out_cities]
            )
          )
        end

        return run.reload if run_canceled?(run)

        deactivate_stale_events!(seen_at: state[:run_started_at])

        finalize_succeeded_run!(
          run,
          state,
          metadata: run_completion_metadata(
            run: run,
            location_whitelist: state[:location_whitelist],
            filtered_out_cities: state[:filtered_out_cities]
          )
        )
      rescue StandardError => e
        handle_import_failure!(
          run,
          state,
          error: e,
          metadata: run_completion_metadata(
            run: run,
            location_whitelist: state&.fetch(:location_whitelist, []),
            filtered_out_cities: state&.fetch(:filtered_out_cities, Set.new)
          )
        )
        raise
      end

      private

      attr_reader :import_source, :dump_fetcher, :detail_fetcher, :run_metadata, :logger

      def upsert_import_event!(attributes:, dump_payload:, detail_payload:, image_candidates:, seen_at:)
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
        Importing::ImportEventImagesSync.call(
          owner: record,
          source: "easyticket",
          candidates: image_candidates
        )
      end

      def deactivate_stale_events!(seen_at:)
        import_source
          .easyticket_import_events
          .where("last_seen_at < ? OR last_seen_at IS NULL", seen_at)
          .update_all(is_active: false)
      end

      def fail_stale_runs!
        fail_stale_runs_by_source!("easyticket")
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
        raw_date = dump_payload["date_time"].to_s.strip if raw_date.blank?
        return nil if raw_date.blank?

        Date.parse(raw_date)
      rescue ArgumentError
        nil
      end

      def build_source_payload_hash(dump_payload)
        Digest::SHA256.hexdigest(dump_payload.to_json)
      end

      def unchanged_payloads?(existing_record, source_payload_hash, detail_payload)
        existing_record.present? &&
          existing_record.source_payload_hash == source_payload_hash &&
          normalized_payload_hash(existing_record.detail_payload) == normalized_payload_hash(detail_payload)
      end

      def mark_existing_event_as_seen!(record:, dump_payload:, detail_payload:, attributes:, seen_at:)
        organizer_id = attributes[:organizer_id].to_s.strip.presence || record.organizer_id

        record.update_columns(
          dump_payload: dump_payload,
          detail_payload: detail_payload,
          organizer_id: organizer_id,
          is_active: true,
          last_seen_at: seen_at,
          updated_at: Time.current
        )
      end

      def normalized_payload_hash(payload)
        value = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}
        Digest::SHA256.hexdigest(JSON.generate(deep_sort_payload(value)))
      end

      def deep_sort_payload(value)
        case value
        when Hash
          value.keys.sort.each_with_object({}) do |key, result|
            result[key] = deep_sort_payload(value[key])
          end
        when Array
          value.map { |entry| deep_sort_payload(entry) }
        else
          value
        end
      end

      def filtered_out_location_label(dump_payload)
        dump_payload["loc_city"].to_s.strip.presence ||
          dump_payload.dig("data", "location", "city").to_s.strip.presence ||
          dump_payload["location_name"].to_s.strip.presence ||
          dump_payload["loc_name"].to_s.strip
      end

      def build_detail_payload(event_id, dump_payload)
        detail_payload = fetch_detail_payload(detail_event_id(event_id, dump_payload), event_id: event_id)
        merge_dump_payload_into_detail_payload(detail_payload, dump_payload)
      end

      def fetch_detail_payload(detail_event_id, event_id:)
        detail_fetcher.fetch(detail_event_id)
      rescue RequestError => e
        raise unless detail_request_not_found?(e)

        logger.warn("[EasyticketImporter] detail payload missing for event_id=#{event_id} detail_event_id=#{detail_event_id}: #{e.message}")
        {}
      end

      def detail_event_id(event_id, dump_payload)
        dump_payload["id"].to_s.strip.presence ||
          dump_payload["title_3"].to_s.strip.presence ||
          event_id
      end

      def detail_request_not_found?(error)
        error.message.to_s.include?("status 404")
      end

      def merge_dump_payload_into_detail_payload(detail_payload, dump_payload)
        payload = detail_payload.is_a?(Hash) ? detail_payload.deep_stringify_keys : {}
        dump_data = dump_payload["data"].is_a?(Hash) ? dump_payload["data"].deep_stringify_keys : {}
        event_date = dump_payload.except("data").deep_stringify_keys

        return payload if dump_data.empty? && event_date.empty?

        data = dump_data
        if payload["data"].is_a?(Hash)
          data = data.merge(payload["data"].deep_stringify_keys)
        end
        data["event"] ||= synthesized_event_payload(dump_payload)
        data["location"] ||= synthesized_location_payload(dump_payload)
        data["event_date"] = event_date if event_date.present? && !data.key?("event_date")

        payload.merge("data" => data)
      end

      def synthesized_event_payload(dump_payload)
        {
          "title_1" => dump_payload["title_1"],
          "title_2" => dump_payload["title_2"],
          "description" => dump_payload["description"],
          "info" => dump_payload["booking_info"],
          "additional_info" => dump_payload["additional_info"],
          "organizer_id" => dump_payload["organizer_id"]
        }.transform_values { |value| value.to_s.strip }.reject { |_, value| value.blank? }
      end

      def synthesized_location_payload(dump_payload)
        {
          "name" => dump_payload["loc_name"].to_s.strip.presence || dump_payload["location_name"].to_s.strip,
          "city" => dump_payload["loc_city"].to_s.strip
        }.reject { |_, value| value.blank? }
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
