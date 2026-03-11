module Backend
  module ImportSources
    class RecentRunSerializer
      def initialize(controller:, registry:, maintenance:)
        @controller = controller
        @registry = registry
        @maintenance = maintenance
      end

      def as_json(run)
        stop_requested = maintenance.stop_requested?(run)
        stop_url = stop_url_for(run)
        can_stop = run.status == "running" && !stop_requested && stop_url.present?

        {
          id: run.id,
          import_source_id: run.import_source_id,
          started_at_label: run.started_at&.strftime("%d.%m.%Y %H:%M:%S"),
          status_label: maintenance.status_label(run),
          status: run.status,
          source_type: run.source_type,
          fetched_count: run.fetched_count,
          filtered_count: run.filtered_count,
          imported_count: run.imported_count,
          upserted_count: run.upserted_count,
          failed_count: run.failed_count,
          can_stop: can_stop,
          stop_url: can_stop ? stop_url : nil
        }
      end

      private

      attr_reader :controller, :maintenance, :registry

      def stop_url_for(run)
        helper_name = registry.fetch(run.source_type, required: false)&.fetch(:stop_route_helper, nil)
        return nil if helper_name.blank?

        controller.public_send(helper_name, run.import_source_id, run_id: run.id)
      end
    end
  end
end
