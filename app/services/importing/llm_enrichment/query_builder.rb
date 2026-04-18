module Importing
  module LlmEnrichment
    class QueryBuilder
      Query = Data.define(:name, :field_name, :query)
      SOCIAL_FIELD_SITES = {
        instagram_link: "instagram.com",
        facebook_link: "facebook.com",
        youtube_link: "youtube.com"
      }.freeze

      def call(event:, field_names: nil)
        Array(field_names || default_field_names).filter_map do |field_name|
          web_search_query(event:, field_name:)
        end
      end

      def web_search_query(event:, field_name:)
        artist_name = quoted_term(event.artist_name)
        return if artist_name.blank?

        case field_name.to_sym
        when :homepage_link
          Query.new(name: "broad", field_name: :homepage_link, query: artist_name)
        when :instagram_link, :facebook_link, :youtube_link
          site = SOCIAL_FIELD_SITES.fetch(field_name.to_sym)
          Query.new(
            name: field_name.to_s.delete_suffix("_link"),
            field_name: field_name.to_sym,
            query: [ artist_name, "site:#{site}" ].join(" ")
          )
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
    end
  end
end
