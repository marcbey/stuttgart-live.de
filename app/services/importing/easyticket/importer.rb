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
        logger: Importing::Logging.logger
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
        @current_run = run
        state = initial_run_state(run:)
        matcher = LocationMatcher.new(state[:location_whitelist])
        events = dump_fetcher.fetch_events(
          heartbeat: -> { touch_run_heartbeat!(run) },
          stop_requested: -> { run_canceled?(run) || stop_requested?(run) }
        )
        state[:fetched_count] = events.size
        return run.reload if run_canceled?(run)

        persist_progress_from_state!(run, state)

        changed_since_flush = 0
        last_flush_at = Time.current

        events.each do |dump_payload|
          if run_canceled?(run) || stop_requested?(run)
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
          detail_payload = build_detail_payload(dump_payload, event_id:)

          source_identifier = source_identifier_for(dump_payload, event_id:)
          RawEventImport.create!(
            import_source: import_source,
            import_event_type: import_source.source_type,
            source_identifier: source_identifier,
            payload: normalize_payload(dump_payload),
            detail_payload: detail_payload
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

        finalize_succeeded_run!(
          run,
          state,
          metadata: run_completion_metadata(
            run: run,
            location_whitelist: state[:location_whitelist],
            filtered_out_cities: state[:filtered_out_cities]
          )
        )
      rescue Importing::StopRequested
        state[:canceled] = true
        persist_progress_from_state!(run, state)
        finalize_canceled_run!(
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
      ensure
        @current_run = nil
      end

      private

      attr_reader :detail_fetcher, :dump_fetcher, :import_source, :logger, :run_metadata

      def fail_stale_runs!(excluding_run_id: nil)
        fail_stale_runs_by_source!("easyticket", excluding_run_id: excluding_run_id)
      end

      def filtered_out_location_label(dump_payload)
        dump_payload["loc_city"].to_s.strip.presence ||
          dump_payload.dig("data", "location", "city").to_s.strip.presence ||
          dump_payload["location_name"].to_s.strip.presence ||
          dump_payload["loc_name"].to_s.strip
      end

      def source_identifier_for(dump_payload, event_id:)
        date_token =
          parse_concert_date_from_dump(dump_payload)&.iso8601 ||
          dump_payload["date"].to_s.strip.presence ||
          dump_payload["date_time"].to_s.strip.presence

        [ event_id, date_token ].compact.join(":")
      end

      def parse_concert_date_from_dump(dump_payload)
        raw_date = dump_payload["date"].to_s.strip
        raw_date = dump_payload["date_time"].to_s.strip if raw_date.blank?
        return nil if raw_date.blank?

        Date.parse(raw_date)
      rescue ArgumentError
        nil
      end

      def normalize_payload(payload)
        payload.is_a?(Hash) ? payload.deep_stringify_keys : {}
      end

      def build_detail_payload(dump_payload, event_id:)
        normalized_dump_payload = normalize_payload(dump_payload)
        return {} unless missing_image_candidates?(normalized_dump_payload)

        fetch_detail_payload(detail_event_id(event_id, normalized_dump_payload), event_id: event_id)
      end

      def missing_image_candidates?(dump_payload)
        projection = Importing::Easyticket::PayloadProjection.new(
          dump_payload: dump_payload,
          detail_payload: {}
        )

        projection.image_candidates.empty?
      end

      def fetch_detail_payload(detail_event_id, event_id:)
        normalize_payload(
          detail_fetcher.fetch(
            detail_event_id,
            heartbeat: -> { touch_run_heartbeat!(@current_run) },
            stop_requested: -> { @current_run.present? && (run_canceled?(@current_run) || stop_requested?(@current_run)) }
          )
        )
      rescue RequestError => e
        raise unless detail_request_not_found?(e)

        logger.warn("[EasyticketImporter] detail payload missing for event_id=#{event_id} detail_event_id=#{detail_event_id}: #{e.message}")
        {}
      end

      def detail_event_id(event_id, dump_payload)
        dump_payload["id"].to_s.strip.presence || event_id
      end

      def detail_request_not_found?(error)
        error.message.to_s.include?("status 404")
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
