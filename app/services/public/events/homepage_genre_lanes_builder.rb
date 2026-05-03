module Public
  module Events
    class HomepageGenreLanesBuilder
      Lane = Data.define(:group, :events, :effective_series_ids, :public_path)

      DEFAULT_LIMIT = 15
      DEFAULT_GROUP_EVENTS_LIMIT = 100

      def initialize(relation:, slugs: nil, limit: DEFAULT_LIMIT)
        @relation = relation
        @slugs = slugs
        @limit = limit
      end

      def call
        return [] if normalized_slugs.empty?

        groups_by_slug = Genre.all.index_by(&:slug)

        normalized_slugs.filter_map do |slug|
          group = groups_by_slug[slug]
          next if group.blank?

          events, effective_series_ids = chronological_group_events(group)
          next if events.empty?

          Lane.new(
            group:,
            events:,
            effective_series_ids:,
            public_path: LaneDirectory.public_path_for_genre_slug(group.slug)
          )
        end
      end

      private

      attr_reader :limit, :relation, :slugs

      def normalized_slugs
        @normalized_slugs ||= AppSetting.normalize_slug_list(
          slugs.nil? ? AppSetting.homepage_genre_lane_slugs : slugs
        )
      end

      def chronological_group_events(group)
        selected_events = group_events(group).limit(candidate_limit).to_a

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

        [ limit * 4, DEFAULT_GROUP_EVENTS_LIMIT ].max
      end

      def group_events(group)
        relation
          .joins(:genres)
          .where(genres: { id: group.id })
          .distinct
          .reorder(:start_at, :id)
      end
    end
  end
end
