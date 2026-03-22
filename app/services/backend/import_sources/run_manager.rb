module Backend
  module ImportSources
    class RunManager
      def initialize(import_source:, registry:, maintenance:, broadcaster: Backend::ImportRunsBroadcaster, dispatcher: nil, enqueuer: nil, stopper: nil)
        @import_source = import_source
        @registry = registry
        @maintenance = maintenance
        @broadcaster = broadcaster
        @dispatcher = dispatcher || Backend::ImportSources::RunDispatcher.new(registry:, broadcaster:)
        @enqueuer = enqueuer || Backend::ImportSources::RunEnqueuer.new(
          registry:,
          maintenance:,
          dispatcher: @dispatcher,
          broadcaster:
        )
        @stopper = stopper || Backend::ImportSources::RunStopper.new(
          registry:,
          dispatcher: @dispatcher,
          broadcaster:
        )
      end

      def trigger(source_type)
        config = registry.fetch(source_type)
        result = enqueuer.call(source_type:, import_source:)
        return { alert: result.alert } if result.alert.present?

        { notice: started_notice_for(config) }
      end

      def request_stop(source_type, run_id: nil)
        label = registry.fetch(source_type).fetch(:label)
        config = registry.fetch(source_type)
        result = stopper.call(source_type:, import_source:, run_id:)
        return { alert: result.alert } if result.alert.present?

        case result.action
        when :canceled_queue
          { notice: canceled_queue_notice_for(config, result.run) }
        else
          { notice: stop_requested_notice_for(config, result.run) }
        end
      end

      private

      attr_reader :broadcaster, :enqueuer, :import_source, :maintenance, :registry, :stopper

      def started_notice_for(config)
        config[:started_notice] || "#{config.fetch(:label)}-Import wurde gestartet."
      end

      def stop_requested_notice_for(config, run)
        builder = config[:stop_requested_notice_builder]
        return builder.call(run) if builder.respond_to?(:call)

        "Stop für #{config.fetch(:label)}-Import (Run ##{run.id}) wurde angefordert."
      end

      def canceled_queue_notice_for(config, run)
        builder = config[:canceled_queue_notice_builder]
        return builder.call(run) if builder.respond_to?(:call)

        "#{config.fetch(:label)}-Import (Run ##{run.id}) wurde aus der Warteschlange entfernt."
      end
    end
  end
end
