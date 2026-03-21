module Public
  module Events
    class RelatedGenreLaneBuilder
      Lane = Data.define(:group, :events)

      DEFAULT_LIMIT = 100

      def initialize(event:, relation:, limit: DEFAULT_LIMIT)
        @event = event
        @relation = relation
        @limit = limit
      end

      def call
        return if group.blank?

        events = prioritized_group_events
        return if events.empty?

        Lane.new(group:, events:)
      end

      private

      attr_reader :event, :limit, :relation

      def group
        @group ||= LlmGenreGrouping::Lookup.groups_for_event(event).first
      end

      def prioritized_group_events
        LlmGenreGrouping::Lookup
          .prioritized_events_for_group(group, relation:, limit:, exclude_event_id: event.id)
          .to_a
      end
    end
  end
end
