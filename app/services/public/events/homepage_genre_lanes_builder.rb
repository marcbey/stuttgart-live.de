module Public
  module Events
    class HomepageGenreLanesBuilder
      Lane = Data.define(:group, :events)

      DEFAULT_LIMIT = 24

      def initialize(relation:, slugs: AppSetting.homepage_genre_lane_slugs, snapshot: LlmGenreGrouping::Lookup.active_snapshot, limit: DEFAULT_LIMIT)
        @relation = relation
        @slugs = Array(slugs)
        @snapshot = snapshot
        @limit = limit
      end

      def call
        return [] if snapshot.blank?
        return [] if normalized_slugs.empty?

        groups_by_slug = snapshot.groups.index_by(&:slug)

        normalized_slugs.filter_map do |slug|
          group = groups_by_slug[slug]
          next if group.blank?

          events = prioritized_group_events(group)
          next if events.empty?

          Lane.new(group:, events:)
        end
      end

      private

      attr_reader :limit, :relation, :slugs, :snapshot

      def normalized_slugs
        @normalized_slugs ||= AppSetting.normalize_slug_list(slugs)
      end

      def prioritized_group_events(group)
        LlmGenreGrouping::Lookup
          .events_for_group(group, relation:)
          .select("events.*, #{priority_order_sql} AS homepage_genre_lane_priority")
          .reorder(Arel.sql("homepage_genre_lane_priority ASC"), :start_at, :id)
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
