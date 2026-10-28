module Public
  module Events
    class HomepageGenreLanesBuilder
      Lane = Data.define(:group, :events, :effective_series_ids, :series_counts_by_id, :public_path, :next_cursor)

      DEFAULT_LIMIT = 10
      DEFAULT_GROUP_EVENTS_LIMIT = 100

      def initialize(relation:, slugs: nil, limit: DEFAULT_LIMIT, include_series_metadata: true)
        @relation = relation
        @slugs = slugs
        @limit = limit
        @include_series_metadata = include_series_metadata
      end

      def call
        return [] if normalized_slugs.empty?

        groups_by_slug = Genre.all.index_by(&:slug)

        lanes = normalized_slugs.filter_map do |slug|
          group = groups_by_slug[slug]
          next if group.blank?

          events, effective_series_ids, series_counts_by_id, next_cursor = chronological_group_events(group)
          next if events.empty?

          Lane.new(
            group:,
            events:,
            effective_series_ids:,
            series_counts_by_id:,
            public_path: public_paths_by_slug[group.slug],
            next_cursor: next_cursor
          )
        end

        preload_lane_associations(lanes)
        lanes
      end

      private

      attr_reader :limit, :relation, :slugs, :include_series_metadata

      def preload_lane_associations(lanes)
        ActiveRecord::Associations::Preloader.new(
          records: lanes.flat_map(&:events),
          associations: relation.includes_values + relation.preload_values
        ).call
      end

      def normalized_slugs
        @normalized_slugs ||= AppSetting.normalize_slug_list(
          slugs.nil? ? AppSetting.homepage_genre_lane_slugs : slugs
        )
      end

      def chronological_group_events(group)
        return unlimited_group_events(group) if limit.nil?

        page = HomepageLanePager.new(
          relation: group_events(group),
          context: lane_context(group),
          per_page: limit
        ).call(include_series_metadata:)

        [ page.events, page.effective_series_ids, page.series_counts_by_id, page.next_cursor ]
      end

      def unlimited_group_events(group)
        selected_events = group_events(group).limit(candidate_limit).to_a

        events = SeriesRepresentativeSelector.call(selected_events)
        events = events.first(limit) if limit.present?
        series_counts_by_id = include_series_metadata ? SeriesCountsByIdQuery.call(events) : {}
        effective_series_ids = include_series_metadata ? effective_series_ids_for(events) : []

        [ events, effective_series_ids, series_counts_by_id, nil ]
      end

      def effective_series_ids_for(events)
        EffectiveSeriesIdsQuery.call(events)
      end

      def candidate_limit
        return if limit.nil?

        [ limit * 4, DEFAULT_GROUP_EVENTS_LIMIT ].max
      end

      def group_events(group)
        candidate_relation = relation.eager_loading? ? relation : relation.except(:includes, :preload)

        candidate_relation
          .joins(:genres)
          .where(genres: { id: group.id })
          .distinct
          .reorder(:start_at, :id)
      end

      def lane_context(group)
        {
          lane: "genre",
          slug: group.slug
        }
      end

      def public_paths_by_slug
        @public_paths_by_slug ||= LaneDirectory.public_paths_for_genre_slugs(normalized_slugs)
      end
    end
  end
end
