require "set"

module Importing
  module Eventim
    class Importer
      include Importing::ImporterExecutionSupport
      include Importing::ImporterRunSupport

      RUN_STALE_AFTER = 1.hour
      RUN_HEARTBEAT_STALE_AFTER = 2.minutes
      PROGRESS_FLUSH_EVERY_N_CHANGES = 1000
      PROGRESS_FLUSH_AFTER_SECONDS = 2
      FILTERED_OUT_CITIES_LIMIT = 500
      PROCESSING_HEARTBEAT_EVERY_N_ROWS = 100

      def initialize(import_source:, feed_fetcher: FeedFetcher.new, preexisting_run_id: nil, run_metadata: {}, logger: Importing::Logging.logger)
        @import_source = import_source
        @feed_fetcher = feed_fetcher
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
        persist_progress_from_state!(run, state)

        changed_since_flush = 0
        last_flush_at = Time.current
        processed_feed_rows = 0

        process_feed_payload = lambda do |feed_payload|
          if run_canceled?(run) || stop_requested?(run)
            state[:canceled] = true
            throw :stop_import
          end

          progress_changed = false
          external_event_id = external_event_id_from_feed(feed_payload)
          state[:fetched_count] += 1
          progress_changed = true
          next if external_event_id.blank?

          unless matcher.match?(feed_payload)
            add_filtered_out_city!(state[:filtered_out_cities], filtered_out_city_from_feed(feed_payload))
            next
          end

          state[:filtered_count] += 1
          normalized_payload = normalize_payload(feed_payload)
          ensure_imported_event_series!(normalized_payload)

          RawEventImport.create!(
            import_source: import_source,
            import_event_type: import_source.source_type,
            source_identifier: source_identifier_for(feed_payload, external_event_id: external_event_id),
            payload: normalized_payload
          )

          state[:imported_count] += 1
          state[:upserted_count] += 1
        rescue StandardError => e
          state[:failed_count] += 1
          progress_changed = true
          logger.error("[EventimImporter] failed: #{e.class}: #{e.message}")
          create_import_run_error!(
            run: run,
            error: e,
            external_event_id: external_event_id,
            payload: feed_payload
          )
        ensure
          processed_feed_rows += 1
          touch_processing_heartbeat!(run, processed_feed_rows)

          next unless progress_changed

          changed_since_flush += 1
          next unless should_flush_progress?(changed_since_flush, last_flush_at)

          persist_progress_from_state!(run, state)
          changed_since_flush = 0
          last_flush_at = Time.current
        end

        begin
          catch(:stop_import) do
            streamed_rows = false
            returned_rows = feed_fetcher.fetch_events(
              heartbeat: -> { touch_run_heartbeat!(run) },
              stop_requested: -> { run_canceled?(run) || stop_requested?(run) }
            ) do |feed_payload|
              streamed_rows = true
              process_feed_payload.call(feed_payload)
            end

            next if streamed_rows

            Array(returned_rows).each do |feed_payload|
              process_feed_payload.call(feed_payload)
            end
          end
        rescue Importing::StopRequested
          state[:canceled] = true
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

      attr_reader :feed_fetcher, :import_source, :logger, :run_metadata

      def fail_stale_runs!(excluding_run_id: nil)
        fail_stale_runs_by_source!("eventim", excluding_run_id: excluding_run_id)
      end

      def source_identifier_for(feed_payload, external_event_id:)
        date_token =
          parse_concert_date_from_feed(feed_payload)&.iso8601 ||
          feed_payload["eventdate"].to_s.strip.presence ||
          feed_payload["date"].to_s.strip.presence

        [ external_event_id.presence || "eventim", date_token ].compact.join(":")
      end

      def parse_concert_date_from_feed(feed_payload)
        payload = normalize_payload(feed_payload)
        Importing::Eventim::PayloadProjection::DATE_KEYS.each do |key|
          raw = payload[key].to_s.strip
          next if raw.blank?

          return Date.parse(raw)
        rescue ArgumentError, TypeError
          next
        end

        nil
      end

      def external_event_id_from_feed(feed_payload)
        hash = normalize_payload(feed_payload)
        PayloadProjection::EVENT_ID_KEYS.each do |key|
          value = hash[key].to_s.strip
          return value if value.present?
        end

        nil
      end

      def filtered_out_city_from_feed(feed_payload)
        hash = normalize_payload(feed_payload)
        keys = Importing::Eventim::LocationMatcher::CITY_KEYS

        keys.each do |key|
          value = hash[key].to_s.strip
          return value if value.present?
        end

        ""
      end

      def normalize_payload(payload)
        payload.is_a?(Hash) ? payload.deep_stringify_keys : {}
      end

      def ensure_imported_event_series!(payload)
        reference = Importing::EventSeriesReference.from_payload(source_type: import_source.source_type, payload: payload)
        return if reference.blank?

        cache_key = [ reference.source_type, reference.source_key ]
        @resolved_event_series_keys ||= Set.new
        return if @resolved_event_series_keys.include?(cache_key)

        EventSeriesResolver.ensure_imported!(reference)
        @resolved_event_series_keys << cache_key
      end

      def run_completion_metadata(run:, location_whitelist:, filtered_out_cities:)
        normalized_metadata(run.metadata).merge(
          "location_whitelist" => Array(location_whitelist),
          "filtered_out_cities" => filtered_out_cities.to_a.sort
        )
      end

      def touch_processing_heartbeat!(run, processed_feed_rows)
        return unless processed_feed_rows.positive?
        return unless (processed_feed_rows % processing_heartbeat_every_n_rows).zero?

        touch_run_heartbeat!(run)
      end

      def processing_heartbeat_every_n_rows
        self.class::PROCESSING_HEARTBEAT_EVERY_N_ROWS
      end
    end
  end
end
