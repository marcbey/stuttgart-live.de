module Public
  module Events
    module Search
      class GenreSuggester
        DEFAULT_LIMIT = 5
        DEFAULT_GENRE_NAMES = [
          "Pop, Indie & Singer-Songwriter",
          "Rock & Alternative",
          "Metal, Punk & Hardcore",
          "Hip-Hop & R’n’B"
        ].freeze

        Suggestion = Data.define(:name, :slug, :path)

        def self.call(query, limit: DEFAULT_LIMIT)
          new(query, limit:).call
        end

        def initialize(query, limit: DEFAULT_LIMIT)
          @query = query.to_s.strip
          @limit = limit
        end

        def call
          return default_suggestions if normalized_query.blank?

          Genre.all.filter_map do |genre|
            rank = match_rank(genre)
            next if rank.blank?

            suggestion = suggestion_for(genre)
            next if suggestion.blank?

            [ rank, static_position(genre), suggestion ]
          end
            .sort_by { |rank, position, suggestion| [ rank, position, suggestion.name ] }
            .first(limit)
            .map(&:third)
        end

        private

        attr_reader :query, :limit

        def default_suggestions
          genres_by_name = Genre.where(name: DEFAULT_GENRE_NAMES).index_by(&:name)

          DEFAULT_GENRE_NAMES.filter_map do |name|
            genre = genres_by_name[name]
            next if genre.blank?

            suggestion_for(genre)
          end.first(limit)
        end

        def suggestion_for(genre)
          path = Public::Events::LaneDirectory.public_path_for_genre_slug(genre.slug)
          return if path.blank?

          Suggestion.new(name: genre.name, slug: genre.slug, path:)
        end

        def normalized_query
          @normalized_query ||= Normalizer.normalize(query)
        end

        def compact_query
          @compact_query ||= Normalizer.compact_normalize(query)
        end

        def match_rank(genre)
          values = normalized_values_for(genre)
          compact_values = compact_values_for(genre)

          return 0 if values.any? { |value| value.start_with?(normalized_query) }
          return 0 if compact_query.present? && compact_values.any? { |value| value.start_with?(compact_query) }
          return 1 if values.any? { |value| value.include?(normalized_query) }
          1 if compact_query.present? && compact_values.any? { |value| value.include?(compact_query) }
        end

        def normalized_values_for(genre)
          [
            Normalizer.normalize(genre.name),
            Normalizer.normalize(genre.slug)
          ].uniq
        end

        def compact_values_for(genre)
          [
            Normalizer.compact_normalize(genre.name),
            Normalizer.compact_normalize(genre.slug)
          ].uniq
        end

        def static_position(genre)
          Genre::STATIC_NAMES.index(genre.name) || Genre::STATIC_NAMES.size
        end
      end
    end
  end
end
