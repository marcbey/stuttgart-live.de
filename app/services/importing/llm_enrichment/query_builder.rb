module Importing
  module LlmEnrichment
    class QueryBuilder
      Query = Data.define(:name, :field_name, :query)

      def call(event:)
        artist_name = quoted_term(event.artist_name)

        [
          Query.new(name: "broad", field_name: :homepage_link, query: artist_name),
          Query.new(name: "instagram", field_name: :instagram_link, query: [ artist_name, "site:instagram.com" ].compact.join(" ")),
          Query.new(name: "facebook", field_name: :facebook_link, query: [ artist_name, "site:facebook.com" ].compact.join(" ")),
          Query.new(name: "youtube", field_name: :youtube_link, query: [ artist_name, "site:youtube.com" ].compact.join(" "))
        ].reject { |query| query.query.blank? }
      end

      private

      def quoted_term(value)
        sanitized = value.to_s.gsub("\"", " ").squish
        return if sanitized.blank?

        %("#{sanitized}")
      end
    end
  end
end
