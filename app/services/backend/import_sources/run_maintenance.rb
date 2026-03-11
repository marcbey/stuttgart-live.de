module Backend
  module ImportSources
    class RunMaintenance
      def initialize(registry:, broadcaster: Backend::ImportRunsBroadcaster, clock: -> { Time.current })
        @registry = registry
        @broadcaster = broadcaster
        @clock = clock
      end

      def release_stale_running_runs!
        ImportRun
          .where(source_type: registry.source_types, status: "running")
          .find_each do |run|
          release_stale_running_run!(run)
        end
      end

      def release_stale_running_run!(run)
        if run.started_at < importer_class_for(run.source_type)::RUN_STALE_AFTER.ago
          fail_stale_run!(run)
          return true
        end

        return false unless heartbeat_stale?(run)

        if stop_requested?(run)
          cancel_stale_stop_requested_run!(run)
        else
          fail_stale_run!(
            run,
            reason: "Run exceeded heartbeat timeout",
            timeout_value: importer_class_for(run.source_type)::RUN_HEARTBEAT_STALE_AFTER
          )
        end
        true
      end

      def stop_requested?(run)
        ActiveModel::Type::Boolean.new.cast(normalized_metadata(run.metadata)["stop_requested"])
      end

      def status_label(run)
        return "running (stop angefordert)" if run.status == "running" && stop_requested?(run)

        run.status
      end

      def normalized_metadata(metadata)
        return {} unless metadata.is_a?(Hash)

        metadata.deep_stringify_keys
      end

      private

      attr_reader :broadcaster, :clock, :registry

      def importer_class_for(source_type)
        registry.fetch(source_type).fetch(:importer_class)
      end

      def heartbeat_stale?(run)
        run.updated_at < importer_class_for(run.source_type)::RUN_HEARTBEAT_STALE_AFTER.ago
      end

      def cancel_stale_stop_requested_run!(run)
        metadata = normalized_metadata(run.metadata)
        metadata["stop_released_at"] = clock.call.iso8601
        metadata["stop_release_reason"] = "No progress update after stop request"
        run.update!(
          status: "canceled",
          finished_at: clock.call,
          metadata: metadata
        )
        broadcaster.broadcast!
      end

      def fail_stale_run!(run, reason: "Run exceeded stale timeout", timeout_value: nil)
        timeout_value ||= importer_class_for(run.source_type)::RUN_STALE_AFTER
        metadata = normalized_metadata(run.metadata)
        metadata["stale_released_at"] = clock.call.iso8601
        metadata["stale_release_reason"] = reason
        run.update!(
          status: "failed",
          finished_at: clock.call,
          metadata: metadata,
          error_message: "Run automatically marked failed after timeout (#{timeout_value.inspect})"
        )
        broadcaster.broadcast!
      end
    end
  end
end
