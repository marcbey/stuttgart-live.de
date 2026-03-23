require "set"

module Importing
  module Reservix
    class Importer
      include Importing::ImporterExecutionSupport
      include Importing::ImporterRunSupport

      RUN_STALE_AFTER = 1.hour
      RUN_HEARTBEAT_STALE_AFTER = 2.minutes
      PROGRESS_FLUSH_EVERY_N_CHANGES = 50
      PROGRESS_FLUSH_AFTER_SECONDS = 2
      FILTERED_OUT_CITIES_LIMIT = 500
      CHECKPOINT_OVERLAP = 5.minutes
      PROCESSING_HEARTBEAT_EVERY_N_ROWS = 50

      def initialize(import_source:, event_fetcher: EventFetcher.new, preexisting_run_id: nil, run_metadata: {}, logger: Importing::Logging.logger)
        @import_source = import_source
        @event_fetcher = event_fetcher
        @preexisting_run_id = preexisting_run_id
        @run_metadata = run_metadata
        @logger = logger
      end

      def call
        prepared_run = prepare_import_run!
        return prepared_run.run unless prepared_run.process

        run = prepared_run.run
        checkpoint = load_checkpoint
        state = initial_run_state(
          run: run,
          checkpoint_tracker: checkpoint_tracker_for(checkpoint)
        )
        matcher = LocationMatcher.new(state[:location_whitelist])

        persist_progress_from_state!(run, state)

        changed_since_flush = 0
        last_flush_at = Time.current
        processed_events = 0

        begin
          catch(:stop_import) do
            event_fetcher.fetch_pages(
              lastupdate: checkpoint_query_value(checkpoint),
              heartbeat: -> { touch_run_heartbeat!(run) },
              stop_requested: -> { run_canceled?(run) || stop_requested?(run) }
            ) do |events, server_time:, **_page_context|
              advance_checkpoint_tracker!(state[:checkpoint_tracker], modified_at: server_time)

              events.each do |event_payload|
                if run_canceled?(run) || stop_requested?(run)
                  state[:canceled] = true
                  throw :stop_import
                end

                progress_changed = false
                payload = normalize_payload(event_payload)
                projection = PayloadProjection.new(event_payload: payload)
                modified_at = projection.modified_at
                external_event_id = payload["id"].to_s.strip
                next if external_event_id.blank?

                advance_checkpoint_tracker!(
                  state[:checkpoint_tracker],
                  modified_at: modified_at,
                  event_id: external_event_id
                )

                state[:fetched_count] += 1
                progress_changed = true

                if already_processed_for_checkpoint?(checkpoint, modified_at: modified_at, event_id: external_event_id)
                  next
                end

                unless matcher.match?(payload)
                  add_filtered_out_city!(state[:filtered_out_cities], filtered_out_city_from_payload(payload))
                  next
                end

                next unless projection.bookable?

                state[:filtered_count] += 1
                ensure_imported_event_series!(payload)

                RawEventImport.create!(
                  import_source: import_source,
                  import_event_type: import_source.source_type,
                  source_identifier: external_event_id,
                  payload: payload
                )

                state[:imported_count] += 1
                state[:upserted_count] += 1
              rescue StandardError => e
                state[:failed_count] += 1
                progress_changed = true
                logger.error("[ReservixImporter] event_id=#{external_event_id} failed: #{e.class}: #{e.message}")
                create_import_run_error!(
                  run: run,
                  error: e,
                  external_event_id: external_event_id,
                  payload: payload
                )
              ensure
                processed_events += 1
                touch_processing_heartbeat!(run, processed_events)

                next unless progress_changed

                changed_since_flush += 1
                next unless should_flush_progress?(changed_since_flush, last_flush_at)

                persist_progress_from_state!(run, state)
                changed_since_flush = 0
                last_flush_at = Time.current
              end
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
              filtered_out_cities: state[:filtered_out_cities],
              checkpoint_tracker: state[:checkpoint_tracker]
            )
          )
        end

        persist_checkpoint!(state[:checkpoint_tracker])

        finalize_succeeded_run!(
          run,
          state,
          metadata: run_completion_metadata(
            run: run,
            location_whitelist: state[:location_whitelist],
            filtered_out_cities: state[:filtered_out_cities],
            checkpoint_tracker: state[:checkpoint_tracker]
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
            filtered_out_cities: state&.fetch(:filtered_out_cities, Set.new),
            checkpoint_tracker: state&.fetch(:checkpoint_tracker, {})
          )
        )
        raise
      end

      private

      attr_reader :event_fetcher, :import_source, :logger, :run_metadata

      def fail_stale_runs!(excluding_run_id: nil)
        fail_stale_runs_by_source!("reservix", excluding_run_id: excluding_run_id)
      end

      def filtered_out_city_from_payload(event_payload)
        payload = normalize_payload(event_payload)
        references = payload["references"].is_a?(Hash) ? payload["references"].deep_stringify_keys : {}
        venue = Array(references["venue"]).find { |entry| entry.is_a?(Hash) }&.deep_stringify_keys || {}

        venue["city"].to_s.strip
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

        return true if modified_at < checkpoint_time
        return false if modified_at > checkpoint_time

        checkpoint[:last_processed_event_id].present? && event_id <= checkpoint[:last_processed_event_id]
      end

      def checkpoint_tracker_for(checkpoint)
        {
          modified_at: checkpoint[:modified_at],
          last_processed_event_id: checkpoint[:last_processed_event_id].to_s
        }
      end

      def advance_checkpoint_tracker!(tracker, modified_at:, event_id: nil)
        return if modified_at.nil?

        current_modified_at = tracker[:modified_at]

        if current_modified_at.nil? || modified_at > current_modified_at
          tracker[:modified_at] = modified_at
          tracker[:last_processed_event_id] = event_id.to_s
        elsif current_modified_at == modified_at
          tracker[:last_processed_event_id] = event_id.to_s if event_id.present?
        end
      end

      def persist_checkpoint!(tracker)
        config = import_source.import_source_config || import_source.build_import_source_config
        config.reservix_checkpoint = {
          "lastupdate" => tracker[:modified_at]&.iso8601,
          "last_processed_event_id" => tracker[:last_processed_event_id]
        }
        config.save!
      end

      def normalize_payload(payload)
        payload.is_a?(Hash) ? payload.deep_stringify_keys : {}
      end

      def run_completion_metadata(run:, location_whitelist:, filtered_out_cities:, checkpoint_tracker:)
        metadata = normalized_metadata(run.metadata).merge(
          "location_whitelist" => Array(location_whitelist),
          "filtered_out_cities" => filtered_out_cities.to_a.sort
        )

        modified_at = checkpoint_tracker[:modified_at]
        return metadata if modified_at.nil?

        metadata.merge(
          "checkpoint" => {
            "lastupdate" => modified_at.iso8601,
            "last_processed_event_id" => checkpoint_tracker[:last_processed_event_id].to_s
          }
        )
      end

      def touch_processing_heartbeat!(run, processed_events)
        return unless processed_events.positive?
        return unless (processed_events % processing_heartbeat_every_n_rows).zero?

        touch_run_heartbeat!(run)
      end

      def processing_heartbeat_every_n_rows
        self.class::PROCESSING_HEARTBEAT_EVERY_N_ROWS
      end
    end
  end
end
