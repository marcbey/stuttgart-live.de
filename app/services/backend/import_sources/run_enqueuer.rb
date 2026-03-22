module Backend
  module ImportSources
    class RunEnqueuer
      Result = Data.define(:run, :alert, :dispatched, :queue_position)

      def initialize(registry:, maintenance:, dispatcher:, broadcaster: Backend::ImportRunsBroadcaster, clock: -> { Time.current })
        @registry = registry
        @maintenance = maintenance
        @dispatcher = dispatcher
        @broadcaster = broadcaster
        @clock = clock
      end

      def call(source_type:, import_source:, run_metadata: {})
        config = registry.fetch(source_type)
        result = nil

        import_source.with_lock do
          release_stale_running_runs_for(source_type, import_source)

          result =
            case config.fetch(:run_mode)
            when :serial_queue
              enqueue_serial_run(source_type:, import_source:, run_metadata:)
            else
              enqueue_exclusive_run(source_type:, import_source:, run_metadata:, config:)
            end
        end

        broadcast_if_needed(result)
        result
      end

      private

      attr_reader :broadcaster, :clock, :dispatcher, :maintenance, :registry

      def enqueue_exclusive_run(source_type:, import_source:, run_metadata:, config:)
        active_run = active_run_for(source_type, import_source)
        if active_run.present?
          return Result.new(
            run: active_run,
            alert: already_running_alert(config, active_run),
            dispatched: false,
            queue_position: nil
          )
        end

        run = import_source.import_runs.create!(
          status: "running",
          source_type: source_type,
          started_at: clock.call,
          metadata: prepared_metadata(run_metadata)
        )
        dispatcher.dispatch_run_locked(run:, source_type:, import_source:)

        Result.new(run:, alert: nil, dispatched: true, queue_position: nil)
      end

      def enqueue_serial_run(source_type:, import_source:, run_metadata:)
        run = import_source.import_runs.create!(
          status: "queued",
          source_type: source_type,
          started_at: clock.call,
          metadata: prepared_metadata(run_metadata).merge(
            "enqueued_at" => clock.call.iso8601
          )
        )
        dispatched_run = dispatcher.dispatch_next_locked(source_type:, import_source:)

        Result.new(
          run: run,
          alert: nil,
          dispatched: dispatched_run&.id == run.id,
          queue_position: queue_position_for(run)
        )
      end

      def active_run_for(source_type, import_source)
        import_source.import_runs.where(source_type: source_type, status: "running").order(started_at: :desc).first
      end

      def release_stale_running_runs_for(source_type, import_source)
        import_source.import_runs.where(source_type: source_type, status: "running").find_each do |run|
          maintenance.release_stale_running_run!(run)
        end
      end

      def queue_position_for(run)
        run.import_source
          .import_runs
          .where(source_type: run.source_type, status: "queued")
          .order(:created_at, :id)
          .pluck(:id)
          .index(run.id)
          &.+(1)
      end

      def prepared_metadata(run_metadata)
        normalized_metadata(run_metadata).reverse_merge(
          "triggered_at" => clock.call.iso8601
        )
      end

      def already_running_alert(config, run)
        builder = config[:already_running_alert_builder]
        return builder.call(run) if builder.respond_to?(:call)

        "Ein #{config.fetch(:label)}-Import läuft bereits (Run ##{run.id})."
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
