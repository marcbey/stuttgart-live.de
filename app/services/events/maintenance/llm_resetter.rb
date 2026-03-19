module Events
  module Maintenance
    class LlmResetter
      Result = Data.define(:event_counts, :import_counts, :queue_counts, :queue_status)

      JOB_CLASS_NAME = "Importing::LlmEnrichment::RunJob".freeze
      SOURCE_TYPE = "llm_enrichment".freeze
      SOLID_QUEUE_EXECUTION_MODELS = [
        [ "solid_queue_blocked_executions", SolidQueue::BlockedExecution ],
        [ "solid_queue_claimed_executions", SolidQueue::ClaimedExecution ],
        [ "solid_queue_failed_executions", SolidQueue::FailedExecution ],
        [ "solid_queue_ready_executions", SolidQueue::ReadyExecution ],
        [ "solid_queue_scheduled_executions", SolidQueue::ScheduledExecution ]
      ].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(
        job_class_name: JOB_CLASS_NAME,
        source_type: SOURCE_TYPE,
        event_model: Event,
        event_change_log_model: EventChangeLog,
        event_llm_enrichment_model: EventLlmEnrichment,
        import_run_model: ImportRun,
        import_run_error_model: ImportRunError,
        solid_queue_job_model: SolidQueue::Job,
        solid_queue_execution_models: SOLID_QUEUE_EXECUTION_MODELS,
        solid_queue_record_class: SolidQueue::Record,
        solid_queue_available: nil,
        queue_configurations: ActiveRecord::Base.configurations
      )
        @job_class_name = job_class_name
        @source_type = source_type
        @event_model = event_model
        @event_change_log_model = event_change_log_model
        @event_llm_enrichment_model = event_llm_enrichment_model
        @import_run_model = import_run_model
        @import_run_error_model = import_run_error_model
        @solid_queue_job_model = solid_queue_job_model
        @solid_queue_execution_models = solid_queue_execution_models
        @solid_queue_record_class = solid_queue_record_class
        @solid_queue_available = solid_queue_available
        @queue_configurations = queue_configurations
      end

      def call
        ActiveRecord::Base.transaction do
          purge_llm_data!
        end

        queue_status = purge_solid_queue_data!

        Result.new(
          event_counts: event_counts,
          import_counts: import_counts,
          queue_counts: queue_counts(queue_status),
          queue_status: queue_status
        )
      end

      private

      attr_reader :event_change_log_model, :event_llm_enrichment_model, :event_model, :import_run_error_model,
        :import_run_model, :job_class_name, :queue_configurations, :solid_queue_execution_models,
        :solid_queue_job_model, :solid_queue_record_class, :source_type

      def purge_llm_data!
        event_llm_enrichment_model.delete_all
        llm_import_run_errors.delete_all
        llm_import_runs.delete_all
        backfill_latest_merge_change_logs!
      end

      def purge_solid_queue_data!
        return :skipped unless solid_queue_available?

        solid_queue_record_class.transaction do
          available_solid_queue_execution_models.each do |(_, model)|
            model.where(job_id: llm_solid_queue_jobs.select(:id)).delete_all
          end

          llm_solid_queue_jobs.delete_all
        end

        :cleared
      end

      def solid_queue_available?
        return @solid_queue_available unless @solid_queue_available.nil?

        return false unless queue_configurations.configs_for(env_name: Rails.env).any? { |config| config.name == "queue" }

        solid_queue_record_class.connection_pool.with_connection do |connection|
          connection.data_source_exists?("solid_queue_jobs")
        end
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
        false
      end

      def event_counts
        {
          "event_llm_enrichments" => event_llm_enrichment_model.count
        }
      end

      def import_counts
        {
          "llm_import_runs" => llm_import_runs.count,
          "llm_import_run_errors" => llm_import_run_errors.count
        }
      end

      def queue_counts(queue_status)
        return {} unless queue_status == :cleared

        available_solid_queue_execution_models.each_with_object({ "solid_queue_jobs" => llm_solid_queue_jobs.count }) do |(name, model), counts|
          counts[name] = model.where(job_id: llm_solid_queue_jobs.select(:id)).count
        end
      end

      def llm_import_runs
        import_run_model.where(source_type: source_type)
      end

      def llm_import_run_errors
        import_run_error_model.where(import_run_id: llm_import_runs.select(:id))
      end

      def llm_solid_queue_jobs
        solid_queue_job_model.where(class_name: job_class_name)
      end

      def available_solid_queue_execution_models
        @available_solid_queue_execution_models ||= solid_queue_execution_models.select do |(_, model)|
          solid_queue_record_class.connection_pool.with_connection do |connection|
            connection.data_source_exists?(model.table_name)
          end
        end
      end

      def latest_successful_merge_run
        import_run_model.where(source_type: "merge", status: "succeeded").order(finished_at: :desc, id: :desc).first
      end

      def backfill_latest_merge_change_logs!
        merge_run = latest_successful_merge_run
        return if merge_run.blank?

        event_ids_with_latest_merge = event_change_log_model
          .where(action: [ "merged_create", "merged_update" ])
          .where("metadata ->> 'merge_run_id' = ?", merge_run.id.to_s)
          .distinct
          .pluck(:event_id)

        missing_event_ids = event_model.where.not(id: event_ids_with_latest_merge).pluck(:id)
        return if missing_event_ids.empty?

        timestamp = Time.current
        event_change_log_model.insert_all(
          missing_event_ids.map do |event_id|
            {
              event_id: event_id,
              action: "merged_update",
              changed_fields: {},
              metadata: { "merge_run_id" => merge_run.id },
              created_at: timestamp,
              updated_at: timestamp
            }
          end
        )
      end
    end
  end
end
