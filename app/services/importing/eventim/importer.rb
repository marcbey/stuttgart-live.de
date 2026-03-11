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

      def initialize(import_source:, feed_fetcher: FeedFetcher.new, preexisting_run_id: nil, run_metadata: {}, logger: Rails.logger)
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

        process_feed_payload = lambda do |feed_payload|
          if run_canceled?(run) || stop_requested?(run)
            state[:canceled] = true
            throw :stop_import
          end

          progress_changed = false

          state[:fetched_count] += 1
          progress_changed = true

          unless matcher.match?(feed_payload)
            add_filtered_out_city!(state[:filtered_out_cities], filtered_out_city_from_feed(feed_payload))
            next
          end

          state[:filtered_count] += 1

          projection = PayloadProjection.new(feed_payload: feed_payload)
          attributes = projection.to_attributes
          if attributes.nil?
            state[:failed_count] += 1
            next
          end

          existing_record = find_existing_import_event(attributes)
          if unchanged_feed_payload?(existing_record, attributes[:source_payload_hash])
            Importing::ImportEventImagesSync.call(
              owner: existing_record,
              source: "eventim",
              candidates: projection.image_candidates
            )
            mark_existing_event_as_seen!(
              record: existing_record,
              feed_payload: feed_payload,
              attributes: attributes,
              seen_at: state[:run_started_at]
            )
            state[:imported_count] += 1
            next
          end

          upsert_import_event!(
            attributes: attributes,
            feed_payload: feed_payload,
            image_candidates: projection.image_candidates,
            seen_at: state[:run_started_at]
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
            external_event_id: external_event_id_from_feed(feed_payload),
            payload: feed_payload
          )
        ensure
          next unless progress_changed

          changed_since_flush += 1
          next unless should_flush_progress?(changed_since_flush, last_flush_at)

          persist_progress_from_state!(run, state)
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
        Importing::ImportEventImagesSync.call(
          owner: record,
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

      def fail_stale_runs!
        fail_stale_runs_by_source!("eventim")
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

      def external_event_id_from_feed(feed_payload)
        hash = feed_payload.is_a?(Hash) ? feed_payload.deep_stringify_keys : {}
        PayloadProjection::EVENT_ID_KEYS.each do |key|
          value = hash[key].to_s.strip
          return value if value.present?
        end

        nil
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
