module Backend
  module ImportSources
    class RunDispatcher
      def initialize(registry:, broadcaster: Backend::ImportRunsBroadcaster, clock: -> { Time.current })
        @registry = registry
        @broadcaster = broadcaster
        @clock = clock
      end

      def dispatch_next(source_type:, import_source:)
        run = nil

        import_source.with_lock do
          run = dispatch_next_locked(source_type:, import_source:)
        end

        broadcast_if_needed(run)
        run
      end

      def dispatch_next_locked(source_type:, import_source:)
        config = registry.fetch(source_type)
        return nil unless config.fetch(:run_mode) == :serial_queue
        return nil if active_or_pending_dispatch?(source_type:, import_source:)

        run = next_dispatchable_queued_run(source_type:, import_source:)
        return nil unless run.present?

        dispatch_run_locked(run:, source_type:, import_source:)
      end

      def dispatch_run_locked(run:, source_type:, import_source:)
        return run if dispatch_requested?(run)

        config = registry.fetch(source_type)
        job = config.fetch(:run_job_class).perform_later(*build_job_arguments(config, import_source, run))

        run.update!(
          metadata: normalized_metadata(run.metadata).merge(
            "dispatch_requested_at" => clock.call.iso8601,
            "job_id" => job.job_id,
            "provider_job_id" => job.provider_job_id,
            "job_attempt" => 1,
            "job_retries_used" => 0,
            "max_retries" => config.fetch(:max_retries)
          )
        )
        run
      end

      def claim_run!(source_type:, import_source:, run_id:)
        claimed_run = nil

        import_source.with_lock do
          run = import_source.import_runs.lock.find_by(id: run_id, source_type: source_type)
          next unless run.present?
          next unless run.status == "queued"

          run.update!(
            status: "running",
            metadata: normalized_metadata(run.metadata).merge(
              "execution_started_at" => clock.call.iso8601
            )
          )
          claimed_run = run
        end

        broadcast_if_needed(claimed_run)
        claimed_run
      end

      private

      attr_reader :clock, :registry

      def active_or_pending_dispatch?(source_type:, import_source:)
        scope = import_source.import_runs.where(source_type: source_type)
        scope.where(status: "running").exists? ||
          scope.where(status: "queued").any? { |run| dispatch_requested?(run) }
      end

      def next_dispatchable_queued_run(source_type:, import_source:)
        import_source
          .import_runs
          .where(source_type: source_type, status: "queued")
          .order(:created_at, :id)
          .detect { |run| !dispatch_requested?(run) }
      end

      def build_job_arguments(config, import_source, run)
        config.fetch(:run_job_arguments_builder).call(import_source, run)
      end

      def dispatch_requested?(run)
        metadata = normalized_metadata(run.metadata)
        metadata["dispatch_requested_at"].present? || metadata["job_id"].present?
      end

      def normalized_metadata(metadata)
        metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
      end

      def broadcast_if_needed(run)
        Backend::ImportRunsBroadcaster.broadcast! if run.present?
      end
    end
  end
end
