module Public
  module Events
    class HomepageGenreTagCloudBuilder
      Tag = Data.define(:name, :slug, :public_path, :upcoming_events_count)

      def initialize(relation:, excluded_slugs: AppSetting.homepage_genre_lane_slugs)
        @relation = relation
        @excluded_slugs = excluded_slugs
      end

      def call
        return [] unless AppSetting.homepage_genre_tag_cloud_enabled?

        ordered_genres.filter_map do |genre|
          next if excluded_slug_list.include?(genre.slug)

          events_count = event_counts_by_genre_id[genre.id].to_i
          next if events_count.zero?

          public_path = LaneDirectory.public_path_for_genre_slug(genre.slug)
          next if public_path.blank?

          Tag.new(
            name: genre.name,
            slug: genre.slug,
            public_path: public_path,
            upcoming_events_count: events_count
          )
        end
      end

      private

      attr_reader :excluded_slugs, :relation

      def ordered_genres
        @ordered_genres ||= Genre.all.to_a.sort_by do |genre|
          Genre::STATIC_NAMES.index(genre.name) || Genre::STATIC_NAMES.size
        end
      end

      def excluded_slug_list
        @excluded_slug_list ||= AppSetting.normalize_slug_list(excluded_slugs)
      end

      def event_counts_by_genre_id
        @event_counts_by_genre_id ||= relation
          .unscope(:order)
          .joins(:genres)
          .where.not(genres: { slug: excluded_slug_list })
          .group("genres.id")
          .count("DISTINCT events.id")
      end
    end
  end
end
