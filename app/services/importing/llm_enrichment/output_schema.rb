module Importing
  module LlmEnrichment
    module OutputSchema
      NAME = "event_llm_enrichment".freeze
      REQUIRED_FIELDS = %w[
        event_id
        genres
        sub_genres
        venue
        event_description
        venue_description
        venue_external_url
        venue_address
        youtube_link
        instagram_link
        homepage_link
        facebook_link
      ].freeze

      module_function

      def format
        {
          type: "json_schema",
          name: NAME,
          strict: true,
          schema: schema
        }
      end

      def schema
        {
          type: "object",
          additionalProperties: false,
          required: REQUIRED_FIELDS,
          properties: properties
        }
      end

      def properties
        {
          event_id: { type: "integer" },
          genres: {
            type: "array",
            minItems: 1,
            maxItems: 3,
            items: { type: "string", enum: Genre::STATIC_NAMES }
          },
          sub_genres: {
            type: "array",
            minItems: 1,
            maxItems: 4,
            items: { type: "string" }
          },
          venue: nullable_string,
          event_description: nullable_string,
          venue_description: nullable_string,
          venue_external_url: nullable_string,
          venue_address: nullable_string,
          youtube_link: nullable_string,
          instagram_link: nullable_string,
          homepage_link: nullable_string,
          facebook_link: nullable_string
        }
      end

      def nullable_string
        { type: [ "string", "null" ] }
      end
    end
  end
end
