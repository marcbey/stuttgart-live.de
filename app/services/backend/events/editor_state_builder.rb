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

      def initialize(inbox_state:, latest_successful_merge_run:, next_event_enabled:)
        @inbox_state = inbox_state
        @latest_successful_merge_run = latest_successful_merge_run
        @next_event_enabled = next_event_enabled
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
        filters[:merge_scope] == "last_merge" ? latest_successful_merge_run&.id : nil
      end

      def build(preferred_event:, navigation_status:)
        target_status = navigation_status || preferred_event.status
        fallback_event = next_event_fallback_for(preferred_event, navigation_status: navigation_status)
        sidebar_events = events_for_status(target_status)

        Result.new(
          target_status: target_status,
          sidebar_events: sidebar_events,
          sidebar_events_count: filtered_events_count(sidebar_events),
          target_event: selected_event_for_sidebar(
            sidebar_events,
            preferred_event: preferred_event,
            fallback_event: fallback_event,
            target_status: target_status
          ),
          merge_run_id: selected_merge_run_id_for_status(target_status)
        )
      end

      private

      attr_reader :inbox_state, :latest_successful_merge_run, :next_event_enabled

      def filters_for(status)
        filters = inbox_state.filters_for(status: status)
        filters[:merge_run_id] = latest_successful_merge_run&.id if filters[:merge_scope] == "last_merge"
        filters
      end

      def next_filtered_event_after(event_id, status:)
        return nil if status.blank?

        events = events_for_status(status).to_a
        index = events.index { |candidate| candidate.id == event_id }
        return nil if index.nil? || events.empty?
        return events.first if index >= events.length - 1

        events[index + 1]
      end

      def next_event_fallback_for(event, navigation_status:)
        next_event_status = navigation_status || event.status
        return nil unless next_event_enabled

        next_filtered_event_after(event.id, status: next_event_status)
      end

      def selected_event_for_sidebar(sidebar_events, preferred_event:, fallback_event:, target_status:)
        if !next_event_enabled && preferred_event.status == target_status
          return preferred_event
        end

        if next_event_enabled && fallback_event
          matched_fallback = sidebar_events.find { |candidate| candidate.id == fallback_event.id }
          return matched_fallback if matched_fallback.present?
        end

        sidebar_events.find { |candidate| candidate.id == preferred_event.id } ||
          (fallback_event && sidebar_events.find { |candidate| candidate.id == fallback_event.id }) ||
          sidebar_events.first
      end
    end
  end
end
