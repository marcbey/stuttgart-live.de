module Public
  module Events
    class RelatedGenreLaneBuilder
      Lane = Data.define(:group, :events, :effective_series_ids)

      DEFAULT_LIMIT = 100

      def initialize(event:, relation:, limit: DEFAULT_LIMIT)
        @event = event
        @relation = relation
        @limit = limit
      end

      def call
        return if group.blank?

        events, effective_series_ids = prioritized_group_events
        return if events.empty?

        Lane.new(group:, events:, effective_series_ids:)
      end

      private

      attr_reader :event, :limit, :relation

      def group
        @group ||= LlmGenreGrouping::Lookup.groups_for_event(event).first
      end

      def prioritized_group_events
        selected_events =
          LlmGenreGrouping::Lookup
            .prioritized_events_for_group(group, relation:, limit: nil, exclude_event_id: event.id)
            .to_a

        effective_series_ids = effective_series_ids_for(selected_events)
        events = SeriesRepresentativeSelector.call(selected_events).first(limit)

        [ events, effective_series_ids ]
      end

      def effective_series_ids_for(events)
        EffectiveSeriesIdsQuery.call(events)
      end
    end
  end
end
