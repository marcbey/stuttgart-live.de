require "digest"
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

      def initialize(import_source:, event_fetcher: EventFetcher.new, preexisting_run_id: nil, run_metadata: {}, logger: Rails.logger)
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

        catch(:stop_import) do
          event_fetcher.fetch_pages(
            lastupdate: checkpoint_query_value(checkpoint),
            heartbeat: -> { touch_run_heartbeat!(run) }
          ) do |events, server_time:, **_page_context|
            advance_checkpoint_tracker!(state[:checkpoint_tracker], modified_at: server_time)

            events.each do |event_payload|
              if run_canceled?(run) || stop_requested?(run)
                state[:canceled] = true
                throw :stop_import
              end

              progress_changed = false
              projection = PayloadProjection.new(event_payload: event_payload)
              modified_at = projection.modified_at
              external_event_id = event_payload["id"].to_s.strip

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

              unless matcher.match?(event_payload)
                add_filtered_out_city!(state[:filtered_out_cities], filtered_out_city_from_payload(event_payload))
                next
              end

              unless projection.bookable?
                if deactivate_existing_import_event!(event_payload: event_payload, seen_at: state[:run_started_at])
                  state[:upserted_count] += 1
                  progress_changed = true
                end
                next
              end

              state[:filtered_count] += 1

              attributes = projection.to_attributes
              if attributes.nil?
                state[:failed_count] += 1
                next
              end

              existing_record = find_existing_import_event(attributes[:external_event_id])
              if unchanged_payload?(existing_record, attributes[:source_payload_hash])
                Importing::ImportEventImagesSync.call(
                  owner: existing_record,
                  source: "reservix",
                  candidates: projection.image_candidates
                )
                mark_existing_event_as_seen!(
                  record: existing_record,
                  event_payload: event_payload,
                  attributes: attributes,
                  seen_at: state[:run_started_at]
                )
                state[:imported_count] += 1
                next
              end

              upsert_import_event!(
                attributes: attributes,
                event_payload: event_payload,
                image_candidates: projection.image_candidates,
                seen_at: state[:run_started_at]
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
                payload: event_payload
              )
            ensure
              next unless progress_changed

              changed_since_flush += 1
              next unless should_flush_progress?(changed_since_flush, last_flush_at)

              persist_progress_from_state!(run, state)
              changed_since_flush = 0
              last_flush_at = Time.current
            end
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
              filtered_out_cities: state[:filtered_out_cities],
              checkpoint_tracker: state[:checkpoint_tracker]
            )
          )
        end

        return run.reload if run_canceled?(run)

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
        Importing::ImportEventImagesSync.call(
          owner: record,
          source: "reservix",
          candidates: image_candidates
        )
      end

      def fail_stale_runs!(excluding_run_id: nil)
        fail_stale_runs_by_source!("reservix", excluding_run_id: excluding_run_id)
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
