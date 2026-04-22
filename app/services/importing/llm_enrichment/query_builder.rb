module Importing
  module LlmEnrichment
    class QueryBuilder
      Query = Data.define(:name, :field_name, :query)
      FACEBOOK_SITE_QUERY = "(official OR band OR music OR artist) site:facebook.com".freeze
      HOMEPAGE_SITE_QUERY = "offizielle website".freeze
      INSTAGRAM_SITE_QUERY = "(official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/".freeze
      YOUTUBE_SITE_QUERY = "site:youtube.com/@ OR site:youtube.com/channel".freeze
      VENUE_EXTERNAL_URL_SITE_QUERY = "offizielle website".freeze

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
        when :venue_external_url
          build_venue_query(event:)
        end
      end

      private

      def default_field_names
        %i[homepage_link instagram_link facebook_link youtube_link venue_external_url]
      end

      def quoted_term(value)
        sanitized = value.to_s.gsub("\"", " ").squish
        return if sanitized.blank?

        %("#{sanitized}")
      end

      def build_query(name:, field_name:, artist_query:, suffix:)
        Query.new(name:, field_name:, query: [ artist_query, suffix ].join(" "))
      end

      def build_venue_query(event:)
        venue_name = venue_name_for_query(event)
        return if venue_name.blank?

        terms = [ quoted_term(venue_name) ]
        city = venue_city_for_query(event)
        terms << quoted_term(city) if city.present?
        terms << VENUE_EXTERNAL_URL_SITE_QUERY

        Query.new(
          name: "venue_external_url",
          field_name: :venue_external_url,
          query: terms.join(" ")
        )
      end

      def venue_name_for_query(event)
        [
          event.respond_to?(:venue) ? event.venue : nil,
          event.respond_to?(:venue_name) ? event.venue_name : nil,
          source_snapshot_value(event, "venue_name")
        ].filter_map { |value| normalize_query_value(value) }.first
      end

      def venue_city_for_query(event)
        [
          event.respond_to?(:city) ? event.city : nil,
          source_snapshot_value(event, "city")
        ].filter_map { |value| normalize_query_value(value) }.first
      end

      def source_snapshot_value(event, key)
        snapshot = event.respond_to?(:source_snapshot) ? event.source_snapshot : nil
        sources = snapshot.is_a?(Hash) ? (snapshot["sources"] || snapshot[:sources]) : nil
        return if sources.blank?

        Array(sources).filter_map do |source|
          next unless source.is_a?(Hash)

          normalize_query_value(source[key] || source[key.to_sym])
        end.first
      end

      def normalize_query_value(value)
        sanitized = value.to_s.squish
        sanitized.presence
      end
    end
  end
end
