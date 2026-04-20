module Importing
  module LlmEnrichment
    class QueryBuilder
      Query = Data.define(:name, :field_name, :query)
      FACEBOOK_SITE_QUERY = "(official OR band OR music OR artist) site:facebook.com".freeze
      HOMEPAGE_SITE_QUERY = "offizielle website".freeze
      INSTAGRAM_SITE_QUERY = "(official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/".freeze
      YOUTUBE_SITE_QUERY = "site:youtube.com/@ OR site:youtube.com/channel".freeze

      def call(event:, field_names: nil)
        Array(field_names || default_field_names).filter_map do |field_name|
          web_search_query(event:, field_name:)
        end
      end

      def web_search_query(event:, field_name:)
        artist_query = quoted_term(Events::ArtistTitleSanitizer.artist_name_for_query(artist_name: event.artist_name, title: event.title))
        return if artist_query.blank?

        case field_name.to_sym
        when :homepage_link
          build_query(name: "broad", field_name: :homepage_link, artist_query:, suffix: HOMEPAGE_SITE_QUERY)
        when :instagram_link
          build_query(name: "instagram", field_name: :instagram_link, artist_query:, suffix: INSTAGRAM_SITE_QUERY)
        when :facebook_link
          build_query(name: "facebook", field_name: :facebook_link, artist_query:, suffix: FACEBOOK_SITE_QUERY)
        when :youtube_link
          build_query(name: "youtube", field_name: :youtube_link, artist_query:, suffix: YOUTUBE_SITE_QUERY)
        end
      end

      private

      def default_field_names
        %i[homepage_link instagram_link facebook_link youtube_link]
      end

      def quoted_term(value)
        sanitized = value.to_s.gsub("\"", " ").squish
        return if sanitized.blank?

        %("#{sanitized}")
      end

      def build_query(name:, field_name:, artist_query:, suffix:)
        Query.new(name:, field_name:, query: [ artist_query, suffix ].join(" "))
      end
    end
  end
end
