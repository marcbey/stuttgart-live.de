module Public
  module Events
    class HomepageGenreLanesBuilder
      Lane = Data.define(:group, :events)

      DEFAULT_LIMIT = 100

      def initialize(relation:, slugs: nil, snapshot: LlmGenreGrouping::Lookup.selected_snapshot, limit: DEFAULT_LIMIT)
        @relation = relation
        @slugs = slugs
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
        @normalized_slugs ||= AppSetting.normalize_slug_list(
          slugs.nil? ? snapshot&.homepage_genre_lane_configuration&.lane_slugs : slugs
        )
      end

      def prioritized_group_events(group)
        LlmGenreGrouping::Lookup
          .prioritized_events_for_group(group, relation:, limit:)
          .to_a
      end
    end
  end
end
