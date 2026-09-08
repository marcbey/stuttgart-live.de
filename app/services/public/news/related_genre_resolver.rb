module Public
  module News
    class RelatedGenreResolver
      EVENT_MATCH_CANDIDATE_LIMIT = 200
      MIN_EVENT_MATCH_LENGTH = 4
      GENERIC_EVENT_TERMS = %w[live tour title event show konzert concerts].freeze
      GENRE_ALIASES_BY_SLUG = {
        "pop-indie-singer-songwriter" => [ "pop", "indie", "singer songwriter", "singer-songwriter" ],
        "rock-alternative" => [ "rock", "alternative" ],
        "metal-punk-hardcore" => [ "metal", "punk", "hardcore" ],
        "hip-hop-r-n-b" => [ "hip hop", "hip-hop", "r n b", "rnb" ],
        "deutschrap" => [ "deutschrap", "deutsch rap" ],
        "schlager-volksmusik" => [ "schlager", "volksmusik" ],
        "techno-house" => [ "techno", "house" ],
        "electronic-music-edm" => [ "electronic music", "electronic", "edm" ],
        "folk-country" => [ "folk", "country" ],
        "weltmusik" => [ "weltmusik", "world music" ],
        "tribute-cover" => [ "tribute", "cover" ],
        "klassik-oper" => [ "klassik", "oper", "opera" ],
        "chor-gospel" => [ "chor", "gospel" ],
        "ausstellungen" => [ "ausstellung", "ausstellungen" ],
        "jazz-blues-soul" => [ "jazz", "blues", "soul" ],
        "musical-theater" => [ "musical", "theater" ],
        "comedy-kabarett" => [ "comedy", "kabarett", "stand up", "stand-up" ],
        "show-variete-performance" => [ "variete", "varieté", "performance" ],
        "lesung-podcast" => [ "lesung", "podcast" ],
        "festivals-openair" => [ "festival", "festivals", "open air", "openair" ],
        "party-night-out" => [ "party", "night out", "clubnacht" ],
        "bildung-wissen" => [ "bildung", "wissen", "vortrag" ],
        "kulinarik-genuss" => [ "kulinarik", "genuss", "kochkurs" ],
        "business-coaching-networking" => [ "business", "coaching", "networking" ],
        "diy-kreativ" => [ "diy", "kreativ", "workshop" ],
        "kultur-fuhrungen-touren" => [ "führung", "fuehrung", "führungen", "fuehrungen", "touren" ],
        "sport-bewegung" => [ "sport", "bewegung", "laufveranstaltung" ]
      }.freeze

      def self.call(blog_post:, relation:)
        new(blog_post:, relation:).call
      end

      def initialize(blog_post:, relation:)
        @blog_post = blog_post
        @relation = relation
      end

      def call
        genre_from_event_mentions || genre_from_article_text
      end

      private
        attr_reader :blog_post, :relation

        def genre_from_event_mentions
          genre_ids = matching_events.flat_map { |event| sorted_association_ids(event, :genres) }.uniq
          return unless genre_ids.one?

          Genre.find_by(id: genre_ids.first)
        end

        def matching_events
          event_candidates.select do |event|
            event_match_terms(event).any? { |term| phrase_present?(article_text, term) }
          end
        end

        def event_candidates
          @event_candidates ||=
            relation
              .joins(:genres)
              .includes(:genres)
              .distinct
              .limit(EVENT_MATCH_CANDIDATE_LIMIT)
              .to_a
        end

        def event_match_terms(event)
          [ event.artist_name, event.title ].filter_map do |value|
            normalized = normalize_text(value)
            next if normalized.delete(" ").length < MIN_EVENT_MATCH_LENGTH
            next if GENERIC_EVENT_TERMS.include?(normalized)

            normalized
          end.uniq
        end

        def genre_from_article_text
          matches = Genre.all.select do |genre|
            genre_aliases(genre).any? { |term| phrase_present?(article_text, term) }
          end

          matches.one? ? matches.first : nil
        end

        def genre_aliases(genre)
          [
            genre.name,
            genre.slug.tr("-", " "),
            *GENRE_ALIASES_BY_SLUG.fetch(genre.slug, [])
          ].filter_map { |term| normalize_text(term) }.uniq
        end

        def article_text
          @article_text ||= normalize_text(
            [
              blog_post.title,
              blog_post.teaser,
              blog_post.body.to_plain_text
            ].join(" ")
          )
        end

        def phrase_present?(text, phrase)
          return false if phrase.blank?

          " #{text} ".include?(" #{phrase} ")
        end

        def normalize_text(value)
          ActiveSupport::Inflector.transliterate(value.to_s)
            .downcase
            .gsub(/[^a-z0-9]+/, " ")
            .squish
        end

        def sorted_association_ids(record, association_name)
          if record.association(association_name).loaded?
            return record.public_send(association_name).map(&:id).sort
          end

          record.public_send(association_name).order(:id).pluck(:id)
        end
    end
  end
end
