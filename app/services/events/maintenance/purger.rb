module Events
  module Maintenance
    class Purger
      Result = Data.define(:event_counts, :import_counts, :solid_queue_counts, :solid_queue_status)

      SOLID_QUEUE_MODELS = [
        [ "solid_queue_blocked_executions", SolidQueue::BlockedExecution ],
        [ "solid_queue_claimed_executions", SolidQueue::ClaimedExecution ],
        [ "solid_queue_failed_executions", SolidQueue::FailedExecution ],
        [ "solid_queue_ready_executions", SolidQueue::ReadyExecution ],
        [ "solid_queue_recurring_executions", SolidQueue::RecurringExecution ],
        [ "solid_queue_scheduled_executions", SolidQueue::ScheduledExecution ],
        [ "solid_queue_jobs", SolidQueue::Job ],
        [ "solid_queue_pauses", SolidQueue::Pause ],
        [ "solid_queue_processes", SolidQueue::Process ],
        [ "solid_queue_semaphores", SolidQueue::Semaphore ]
      ].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(
        include_imports: false,
        include_solid_queue: false,
        solid_queue_models: SOLID_QUEUE_MODELS,
        solid_queue_record_class: SolidQueue::Record,
        solid_queue_available: nil,
        queue_configurations: ActiveRecord::Base.configurations
      )
        @include_imports = include_imports
        @include_solid_queue = include_solid_queue
        @solid_queue_models = solid_queue_models
        @solid_queue_record_class = solid_queue_record_class
        @solid_queue_available = solid_queue_available
        @queue_configurations = queue_configurations
      end

      def call
        ActiveRecord::Base.transaction do
          purge_event_data!
          purge_import_data! if include_imports?
        end

        solid_queue_status = purge_solid_queue_data!

        Result.new(
          event_counts: event_counts,
          import_counts: import_counts,
          solid_queue_counts: solid_queue_counts(solid_queue_status),
          solid_queue_status: solid_queue_status
        )
      end

      private

      attr_reader :queue_configurations, :solid_queue_models, :solid_queue_record_class

      def include_imports?
        @include_imports
      end

      def include_solid_queue?
        @include_solid_queue
      end

      def purge_event_data!
        EventImage.delete_all
        ImportEventImage.where(import_class: "Event").delete_all
        EventOffer.delete_all
        EventGenre.delete_all
        EventChangeLog.delete_all
        Event.delete_all
      end

      def purge_import_data!
        ImportRunError.delete_all
        ImportRun.delete_all
        RawEventImport.delete_all
        reset_import_source_checkpoints!
      end

      def reset_import_source_checkpoints!
        ImportSourceConfig.find_each do |config|
          next if config.reservix_checkpoint.blank?

          config.update!(settings: config.settings.except(ImportSourceConfig::RESERVIX_CHECKPOINT_KEY))
        end
      end

      def purge_solid_queue_data!
        return :not_requested unless include_solid_queue?
        return :skipped unless solid_queue_available?

        solid_queue_record_class.transaction do
          solid_queue_models.each do |(_, model)|
            model.delete_all
          end
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
          "events" => Event.count,
          "event_offers" => EventOffer.count,
          "event_genres" => EventGenre.count,
          "event_change_logs" => EventChangeLog.count,
          "event_images" => EventImage.count,
          "event_import_images" => ImportEventImage.where(import_class: "Event").count,
          "raw_event_imports" => RawEventImport.count
        }
      end

      def import_counts
        return {} unless include_imports?

        {
          "import_runs" => ImportRun.count,
          "import_run_errors" => ImportRunError.count,
          "reservix_checkpoints" => reservix_checkpoint_count
        }
      end

      def solid_queue_counts(solid_queue_status)
        return {} unless solid_queue_status == :cleared

        solid_queue_models.each_with_object({}) do |(name, model), counts|
          counts[name] = model.count
        end
      end

      def reservix_checkpoint_count
        ImportSourceConfig.find_each.count { |config| config.reservix_checkpoint.present? }
      end
    end
  end
end
