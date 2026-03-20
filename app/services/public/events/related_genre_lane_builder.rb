module Public
  module Events
    class RelatedGenreLaneBuilder
      Lane = Data.define(:group, :events)

      DEFAULT_LIMIT = 24

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
          .events_for_group(group, relation:)
          .where.not(id: event.id)
          .select("events.*, #{priority_order_sql} AS related_genre_lane_priority")
          .reorder(Arel.sql("related_genre_lane_priority ASC"), :start_at, :id)
          .limit(limit)
          .to_a
      end

      def priority_order_sql
        quoted_ids = Event.sks_promoter_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(", ")
        sks_clause = quoted_ids.present? ? "WHEN events.promoter_id IN (#{quoted_ids}) THEN 1 " : ""

        "CASE WHEN events.highlighted = TRUE THEN 0 #{sks_clause}ELSE 2 END"
      end
    end
  end
end
