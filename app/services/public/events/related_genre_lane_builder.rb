module Public
  module Events
    class RelatedGenreLaneBuilder
      Lane = Data.define(:group, :events, :effective_series_ids)

      DEFAULT_LIMIT = 100
      DEFAULT_GROUP_EVENTS_LIMIT = 100

      def initialize(event:, relation:, limit: DEFAULT_LIMIT)
        @event = event
        @relation = relation
        @limit = limit
      end

      def call
        return if group.blank?

        events, effective_series_ids = chronological_group_events
        return if events.empty?

        Lane.new(group:, events:, effective_series_ids:)
      end

      private

      attr_reader :event, :limit, :relation

      def group
        @group ||= event.primary_genre
      end

      def chronological_group_events
        selected_events = relation
          .joins(:genres)
          .where(genres: { id: group.id })
          .where.not(id: event.id)
          .distinct
          .reorder(:start_at, :id)
          .limit(candidate_limit)
          .to_a

        events = SeriesRepresentativeSelector.call(selected_events).first(limit)
        effective_series_ids = effective_series_ids_for(events)

        [ events, effective_series_ids ]
      end

      def effective_series_ids_for(events)
        EffectiveSeriesIdsQuery.call(events)
      end

      def candidate_limit
        [ limit * 4, DEFAULT_GROUP_EVENTS_LIMIT ].max
      end
    end
  end
end
