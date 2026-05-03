module Backend
  module ImportSources
    class LlmEnrichmentRunResumer
      Result = Data.define(:run, :alert, :notice)

      RESUMABLE_STATUSES = %w[failed canceled].freeze

      def initialize(registry:, maintenance:, dispatcher:, clock: -> { Time.current })
        @registry = registry
        @maintenance = maintenance
        @dispatcher = dispatcher
        @clock = clock
      end

      def call(source_run:)
        return Result.new(run: nil, alert: "Dieser Run kann nicht fortgesetzt werden.", notice: nil) unless resumable?(source_run)

        result = enqueuer.call(
          source_type: "llm_enrichment",
          import_source: source_run.import_source,
          run_metadata: resume_metadata_for(source_run)
        )

        return Result.new(run: result.run, alert: result.alert, notice: nil) if result.alert.present?

        Result.new(
          run: result.run,
          alert: nil,
          notice: resume_notice(dispatched: result.dispatched, queue_position: result.queue_position)
        )
      end

      private

      attr_reader :clock, :dispatcher, :maintenance, :registry

      def resumable?(run)
        run.source_type == "llm_enrichment" &&
          RESUMABLE_STATUSES.include?(run.status) &&
          normalized_metadata(run.metadata)["trigger_scope"] != "single_event"
      end

      def resume_metadata_for(source_run)
        source_metadata = normalized_metadata(source_run.metadata)
        metadata = {
          "triggered_at" => clock.call.iso8601,
          "trigger_scope" => "all_future_events",
          "refresh_existing" => true,
          "resume_source_run_id" => source_run.id,
          "resume_source_run_status" => source_run.status,
          "selection_started_at" => selection_started_at_for(source_run, source_metadata)
        }

        metadata.merge(resume_cursor_metadata(source_metadata))
      end

      def selection_started_at_for(source_run, source_metadata)
        source_metadata["selection_started_at"].to_s.presence || source_run.started_at.iso8601
      end

      def resume_cursor_metadata(source_metadata)
        current_cursor = cursor_metadata(source_metadata, "current", inclusive: true)
        return current_cursor if current_cursor.present?

        cursor_metadata(source_metadata, "last_completed", inclusive: false)
      end

      def cursor_metadata(source_metadata, prefix, inclusive:)
        event_id = Integer(source_metadata["#{prefix}_event_id"], exception: false)
        start_at = source_metadata["#{prefix}_event_start_at"].to_s.presence
        return {} if event_id.blank? || start_at.blank?

        {
          "resume_from_event_id" => event_id,
          "resume_from_start_at" => start_at,
          "resume_from_inclusive" => inclusive
        }
      end

      def resume_notice(dispatched:, queue_position:)
        return "LLM-Enrichment-Fortsetzung wurde gestartet." if dispatched
        return "LLM-Enrichment-Fortsetzung wurde zur Warteschlange hinzugefügt." if queue_position.blank?

        "LLM-Enrichment-Fortsetzung wurde zur Warteschlange hinzugefügt (Position #{queue_position})."
      end

      def enqueuer
        @enqueuer ||= Backend::ImportSources::RunEnqueuer.new(
          registry: registry,
          maintenance: maintenance,
          dispatcher: dispatcher
        )
      end

      def normalized_metadata(metadata)
        metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
      end
    end
  end
end
