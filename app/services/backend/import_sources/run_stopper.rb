module Backend
  module ImportSources
    class RunStopper
      Result = Data.define(:run, :alert, :action)

      def initialize(registry:, dispatcher:, broadcaster: Backend::ImportRunsBroadcaster, clock: -> { Time.current })
        @registry = registry
        @dispatcher = dispatcher
        @broadcaster = broadcaster
        @clock = clock
      end

      def call(source_type:, import_source:, run_id: nil)
        config = registry.fetch(source_type)
        result = nil

        import_source.with_lock do
          run = find_active_run(source_type:, import_source:, run_id:)
          unless run.present?
            result = Result.new(run: nil, alert: "Kein laufender #{config.fetch(:label)}-Import gefunden.", action: nil)
            next
          end

          result =
            case run.status
            when "queued"
              cancel_queued_run(run, source_type:, import_source:)
            when "running"
              request_stop_for_running_run(run)
            else
              Result.new(run: nil, alert: "Kein laufender #{config.fetch(:label)}-Import gefunden.", action: nil)
            end
        end

        broadcast_if_needed(result)
        result
      end

      private

      attr_reader :broadcaster, :clock, :dispatcher, :registry

      def find_active_run(source_type:, import_source:, run_id:)
        scope = import_source.import_runs.where(source_type: source_type).order(started_at: :desc, created_at: :desc)
        active_scope = scope.where(status: %w[queued running])
        return active_scope.find_by(id: run_id) if run_id.present?

        active_scope.where(status: "running").first || active_scope.where(status: "queued").first
      end

      def request_stop_for_running_run(run)
        return force_cancel_running_single_event_run(run) if force_cancel_running_single_event_run?(run)

        metadata = normalized_metadata(run.metadata)
        metadata["stop_requested"] = true
        metadata["stop_requested_at"] = clock.call.iso8601
        run.update!(metadata: metadata)

        Result.new(run:, alert: nil, action: :stop_requested)
      end

      def force_cancel_running_single_event_run?(run)
        run.source_type == "llm_enrichment" && normalized_metadata(run.metadata)["trigger_scope"] == "single_event"
      end

      def force_cancel_running_single_event_run(run)
        metadata = normalized_metadata(run.metadata)
        metadata["stop_requested"] = true
        metadata["stop_requested_at"] ||= clock.call.iso8601
        metadata["stop_released_at"] = clock.call.iso8601
        metadata["stop_release_reason"] = "Force-stopped single-event run"

        run.update!(
          status: "canceled",
          finished_at: clock.call,
          metadata: metadata
        )
        dispatcher.dispatch_next_locked(source_type: run.source_type, import_source: run.import_source)

        Result.new(run:, alert: nil, action: :forced_cancel)
      end

      def cancel_queued_run(run, source_type:, import_source:)
        metadata = normalized_metadata(run.metadata)
        metadata["stop_released_at"] = clock.call.iso8601
        metadata["stop_release_reason"] = "Canceled before execution"
        run.update!(
          status: "canceled",
          finished_at: clock.call,
          metadata: metadata
        )
        dispatcher.dispatch_next_locked(source_type:, import_source:)

        Result.new(run:, alert: nil, action: :canceled_queue)
      end

      def normalized_metadata(metadata)
        metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
      end

      def broadcast_if_needed(result)
        broadcaster.broadcast! if result.run.present?
      end
    end
  end
end
