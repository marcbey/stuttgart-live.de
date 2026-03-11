module Backend
  module ImportSources
    class RunManager
      def initialize(import_source:, registry:, maintenance:, broadcaster: Backend::ImportRunsBroadcaster)
        @import_source = import_source
        @registry = registry
        @maintenance = maintenance
        @broadcaster = broadcaster
      end

      def trigger(source_type)
        config = registry.fetch(source_type)
        release_stale_running_runs_for(source_type)
        active_run = active_run_for(source_type)

        if active_run.present?
          return {
            alert: "Ein #{config.fetch(:label)}-Import läuft bereits (Run ##{active_run.id})."
          }
        end

        run = import_source.import_runs.create!(
          status: "running",
          source_type: source_type,
          started_at: Time.current,
          metadata: { "triggered_at" => Time.current.iso8601 }
        )
        job = config.fetch(:run_job_class).perform_later(import_source.id, run.id)
        run.update!(
          metadata: maintenance.normalized_metadata(run.metadata).merge(
            "job_id" => job.job_id,
            "provider_job_id" => job.provider_job_id,
            "job_attempt" => 1,
            "job_retries_used" => 0,
            "max_retries" => Importing::RetryPolicy::RETRY_DELAYS.size
          )
        )
        broadcaster.broadcast!
        {}
      end

      def request_stop(source_type, run_id: nil)
        label = registry.fetch(source_type).fetch(:label)
        run = find_running_run_for_stop(source_type, run_id:)
        return { alert: "Kein laufender #{label}-Import gefunden." } unless run

        metadata = maintenance.normalized_metadata(run.metadata)
        metadata["stop_requested"] = true
        metadata["stop_requested_at"] = Time.current.iso8601
        metadata["stop_released_at"] = Time.current.iso8601
        metadata["stop_release_reason"] = "Stopped by user"
        run.update!(
          status: "canceled",
          finished_at: Time.current,
          metadata: metadata
        )
        broadcaster.broadcast!

        { notice: "Stop für #{label}-Import (Run ##{run.id}) wurde angefordert." }
      end

      private

      attr_reader :broadcaster, :import_source, :maintenance, :registry

      def active_run_for(source_type)
        import_source.import_runs.where(source_type: source_type, status: "running").order(started_at: :desc).first
      end

      def release_stale_running_runs_for(source_type)
        import_source.import_runs.where(source_type: source_type, status: "running").find_each do |run|
          maintenance.release_stale_running_run!(run)
        end
      end

      def find_running_run_for_stop(source_type, run_id:)
        scope = import_source.import_runs.where(source_type: source_type, status: "running").order(started_at: :desc)
        return scope.find_by(id: run_id) if run_id.present?

        scope.first
      end
    end
  end
end
