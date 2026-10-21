module Backend
  module Events
    class EditorStateBuilder
      Result = Data.define(
        :target_status,
        :sidebar_events,
        :sidebar_events_count,
        :target_event,
        :merge_run_id
      )

      def initialize(inbox_state:, event_loader: nil)
        @inbox_state = inbox_state
        @event_loader = event_loader || ->(event) { event }
      end

      def events_for_status(status)
        filters = filters_for(status)
        Editorial::EventsInboxQuery.new(params: filters).call
      end

      def filtered_events_count(relation)
        relation.except(:limit).count
      end

      def selected_merge_run_id_for_status(status)
        filters = filters_for(status)
        Integer(filters[:merge_run_id], exception: false)
      end

      def build(preferred_event:, navigation_status:)
        target_status = navigation_status || preferred_event.status
        sidebar_relation = events_for_status(target_status)
        sidebar_events = sidebar_relation.to_a

        Result.new(
          target_status: target_status,
          sidebar_events: sidebar_events,
          sidebar_events_count: filtered_events_count(sidebar_relation),
          target_event: load_event_for_editor(preferred_event),
          merge_run_id: selected_merge_run_id_for_status(target_status)
        )
      end

      private

      attr_reader :event_loader, :inbox_state

      def filters_for(status)
        inbox_state.filters_for(status: status)
      end

      def load_event_for_editor(event)
        return if event.blank?

        event_loader.call(event)
      end
    end
  end
end
