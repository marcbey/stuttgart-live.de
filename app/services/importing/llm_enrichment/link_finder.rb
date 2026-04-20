require "uri"

module Importing
  module LlmEnrichment
    class LinkFinder
      LINK_FIELDS = %i[homepage_link instagram_link facebook_link youtube_link].freeze
      GOOGLE_RESULT_LIMIT = 10

      Result = Data.define(
        :links,
        :payload,
        :web_search_request_count,
        :web_search_candidate_count,
        :links_found_via_web_search_count,
        :links_null_after_link_lookup_count,
        :validation_results
      )

      def initialize(
        web_search_provider: AppSetting.llm_enrichment_web_search_provider,
        web_search_client: WebSearchClientFactory.build(provider: web_search_provider),
        query_builder: QueryBuilder.new,
        link_validator: nil
      )
        @web_search_provider = web_search_provider
        @web_search_client = web_search_client
        @query_builder = query_builder
      end

      def call(event:)
        web_queries_payload = []
        fields_payload = {}
        links = {}
        web_search_candidate_count = 0
        found_count = 0

        query_builder.call(event:).each do |query|
          search_payload, selected_candidate = run_web_search_query(query:)
          selected_url = selected_candidate&.fetch("url", nil)

          web_queries_payload << search_payload
          web_search_candidate_count += 1 if selected_candidate.present?
          fields_payload[query.field_name.to_s] = {
            "query_name" => query.name,
            "query" => query.query,
            "selected_url" => selected_url,
            "candidates" => selected_candidate.present? ? [ selected_candidate ] : []
          }
          links[query.field_name.to_sym] = selected_url
          found_count += 1 if selected_url.present?
        end

        Result.new(
          links: links,
          payload: {
            "web_search_provider" => web_search_provider,
            "queries" => web_queries_payload,
            "fields" => fields_payload
          },
          web_search_request_count: web_queries_payload.size,
          web_search_candidate_count: web_search_candidate_count,
          links_found_via_web_search_count: found_count,
          links_null_after_link_lookup_count: LINK_FIELDS.size - found_count,
          validation_results: []
        )
      end

      private

      attr_reader :query_builder, :web_search_client, :web_search_provider

      def run_web_search_query(query:)
        search_result = web_search_client.search(query: query.query, num: GOOGLE_RESULT_LIMIT)
        first_result = Array(search_result.organic_results).first
        candidate = build_candidate(organic_result: first_result, query:, search_id: search_result.search_id)

        [
          {
            "name" => query.name,
            "field_name" => query.field_name.to_s,
            "query" => query.query,
            "search_id" => search_result.search_id,
            "provider" => web_search_provider
          },
          candidate
        ]
      rescue StandardError => e
        [
          {
            "name" => query.name,
            "field_name" => query.field_name.to_s,
            "query" => query.query,
            "provider" => web_search_provider,
            "error_class" => e.class.to_s,
            "error_message" => e.message
          },
          nil
        ]
      end

      def build_candidate(organic_result:, query:, search_id:)
        return if organic_result.blank?

        uri = parse_http_uri(organic_result.link)
        return if uri.blank?

        normalized_uri = normalize_candidate_uri(uri, field_name: query.field_name.to_sym)
        return if normalized_uri.blank?

        {
          "url" => normalized_uri.to_s,
          "title" => organic_result.title,
          "snippet" => organic_result.snippet,
          "position" => organic_result.position,
          "query_name" => query.name,
          "query" => query.query,
          "search_id" => search_id,
          "source_type" => "web_search",
          "selected" => true,
          "selection_strategy" => "first_search_result"
        }.compact
      end

      def parse_http_uri(value)
        uri = URI.parse(value)
        return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return if uri.host.blank?

        uri
      rescue URI::InvalidURIError
        nil
      end

      def normalize_candidate_uri(uri, field_name:)
        normalized_uri = uri.dup

        case field_name
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
  end
end
