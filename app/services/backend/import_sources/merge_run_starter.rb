module Backend
  module ImportSources
    class MergeRunStarter
      Result = Data.define(:run, :notice, :alert)

      def initialize(
        registry: Backend::ImportSources::ImporterRegistry.new,
        broadcaster: Backend::ImportRunsBroadcaster,
        clock: -> { Time.current },
        job_class: Merging::SyncImportedEventsJob
      )
        @registry = registry
        @broadcaster = broadcaster
        @clock = clock
        @job_class = job_class
      end

      def call(run_metadata: {})
        result = nil

        run_source.with_lock do
          active_run = ImportRun.where(source_type: "merge", status: "running").order(started_at: :desc).first
          if active_run.present?
            result = Result.new(run: active_run, notice: nil, alert: "Ein Merge-Run läuft bereits (Run ##{active_run.id}).")
            next
          end

          run = run_source.import_runs.create!(
            source_type: "merge",
            status: "running",
            started_at: clock.call,
            metadata: prepared_metadata(run_metadata)
          )
          job = job_class.perform_later(import_run_id: run.id)
          run.update!(
            metadata: run.metadata.merge(
              "job_id" => job.job_id,
              "provider_job_id" => job.provider_job_id,
              "job_attempt" => 1,
              "job_retries_used" => 0,
              "max_retries" => 0
            )
          )
          broadcaster.broadcast!

          result = Result.new(run:, notice: "Merge-Sync wurde gestartet.", alert: nil)
        end

        result
      end

      private

      attr_reader :broadcaster, :clock, :job_class, :registry

      def prepared_metadata(run_metadata)
        normalized_metadata(run_metadata).reverse_merge(
          "triggered_at" => clock.call.iso8601
        )
      end

      def normalized_metadata(run_metadata)
        run_metadata.is_a?(Hash) ? run_metadata.deep_stringify_keys : {}
      end

      def run_source
        @run_source ||= registry.resolve_run_source("merge")
      end
    end
  end
end
