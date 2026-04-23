module Public
  module Events
    class HomepageGenreLanesBuilder
      Lane = Data.define(:group, :events, :effective_series_ids, :public_path)
      LaneGroup = Data.define(:name, :slug)

      DEFAULT_LIMIT = 15

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

          events, effective_series_ids = chronological_group_events(group)
          next if events.empty?

          Lane.new(
            group:,
            events:,
            effective_series_ids:,
            public_path: LaneDirectory.public_path_for_genre_slug(group.slug, snapshot: snapshot)
          )
        end
      end

      private

      attr_reader :limit, :relation, :slugs, :snapshot

      def normalized_slugs
        @normalized_slugs ||= AppSetting.normalize_slug_list(
          slugs.nil? ? snapshot&.homepage_genre_lane_configuration&.lane_slugs : slugs
        )
      end

      def chronological_group_events(group)
        selected_events =
          LlmGenreGrouping::Lookup
            .chronological_events_for_group(group, relation:, limit: candidate_limit)
            .to_a

        events = SeriesRepresentativeSelector.call(selected_events)
        events = events.first(limit) if limit.present?
        effective_series_ids = effective_series_ids_for(events)

        [ events, effective_series_ids ]
      end

      def effective_series_ids_for(events)
        EffectiveSeriesIdsQuery.call(events)
      end

      def candidate_limit
        return if limit.nil?

        [ limit * 4, LlmGenreGrouping::Lookup::DEFAULT_GROUP_EVENTS_LIMIT ].max
      end
    end
  end
end
