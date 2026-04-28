require "uri"

module Importing
  module LlmEnrichment
    class LinkFinder
      LINK_FIELDS = %i[homepage_link instagram_link facebook_link youtube_link].freeze
      GOOGLE_RESULT_LIMIT = 10

      Result = Data.define(
        :payload,
        :web_search_request_count,
        :web_search_candidate_count
      )

      class << self
        def normalize_candidate_url(value, field_name:)
          uri = parse_http_uri(value)
          return if uri.blank?

          normalize_candidate_uri(uri, field_name:).to_s
        end

        private

        def parse_http_uri(value)
          uri = URI.parse(value.to_s)
          return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          return if uri.host.blank?

          uri
        rescue URI::InvalidURIError
          nil
        end

        def normalize_candidate_uri(uri, field_name:)
          normalized_uri = uri.dup

          case field_name.to_sym
          when :instagram_link
            normalize_instagram_uri(normalized_uri)
          else
            normalized_uri
          end
        end

        def normalize_instagram_uri(uri)
          host = uri.host.to_s.downcase
          return uri unless %w[instagram.com www.instagram.com secure.instagram.com].include?(host)

          uri.host = "www.instagram.com"
          uri.query = nil
          uri.fragment = nil
          uri
        end
      end

      def initialize(
        web_search_provider: AppSetting.llm_enrichment_web_search_provider,
        web_search_client: WebSearchClientFactory.build(provider: web_search_provider),
        query_builder: QueryBuilder.new
      )
        @web_search_provider = web_search_provider
        @web_search_client = web_search_client
        @query_builder = query_builder
      end

      def call(event:)
        web_queries_payload = []
        fields_payload = default_fields_payload
        web_search_candidate_count = 0

        query_builder.call(event:).each do |query|
          search_payload, field_payload, candidate_count = run_web_search_query(query:)
          web_queries_payload << search_payload
          fields_payload[query.field_name.to_s] = field_payload
          web_search_candidate_count += candidate_count
        end

        Result.new(
          payload: {
            "web_search_provider" => web_search_provider,
            "queries" => web_queries_payload,
            "fields" => fields_payload
          },
          web_search_request_count: web_queries_payload.size,
          web_search_candidate_count: web_search_candidate_count
        )
      end

      private

      attr_reader :query_builder, :web_search_client, :web_search_provider

      def default_fields_payload
        LINK_FIELDS.index_with do
          {
            "query_name" => nil,
            "query" => nil,
            "provider" => web_search_provider,
            "search_id" => nil,
            "candidates" => []
          }
        end.deep_stringify_keys
      end

      def run_web_search_query(query:)
        search_result = web_search_client.search(query: query.query, num: GOOGLE_RESULT_LIMIT)
        candidates = Array(search_result.organic_results)
          .filter_map { |organic_result| build_candidate(organic_result:, query:, search_id: search_result.search_id) }

        [
          {
            "name" => query.name,
            "field_name" => query.field_name.to_s,
            "query" => query.query,
            "search_id" => search_result.search_id,
            "provider" => web_search_provider
          },
          {
            "query_name" => query.name,
            "query" => query.query,
            "provider" => web_search_provider,
            "search_id" => search_result.search_id,
            "candidates" => candidates
          },
          candidates.size
        ]
      rescue StandardError => e
        raise if e.is_a?(WebSearchResponse::FatalError)

        [
          {
            "name" => query.name,
            "field_name" => query.field_name.to_s,
            "query" => query.query,
            "provider" => web_search_provider,
            "error_class" => e.class.to_s,
            "error_message" => e.message
          },
          {
            "query_name" => query.name,
            "query" => query.query,
            "provider" => web_search_provider,
            "search_id" => nil,
            "candidates" => [],
            "error_class" => e.class.to_s,
            "error_message" => e.message
          },
          0
        ]
      end

      def build_candidate(organic_result:, query:, search_id:)
        normalized_url = self.class.normalize_candidate_url(organic_result.link, field_name: query.field_name)
        return if normalized_url.blank?

        {
          "position" => organic_result.position,
          "title" => organic_result.title.to_s,
          "link" => normalized_url,
          "displayed_link" => organic_result.displayed_link.to_s.presence,
          "snippet" => organic_result.snippet.to_s.presence,
          "source" => organic_result.source.to_s.presence,
          "about_source_description" => organic_result.about_source_description.to_s.presence,
          "languages" => Array(organic_result.languages).presence,
          "regions" => Array(organic_result.regions).presence,
          "search_id" => search_id
        }.compact
      end
    end
  end
end
