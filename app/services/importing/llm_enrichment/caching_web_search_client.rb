module Importing
  module LlmEnrichment
    class CachingWebSearchClient
      CACHE_VERSION = "v1".freeze
      CACHE_TTL = 1.week
      OrganicResult = WebSearchResponse::OrganicResult
      SearchResult = WebSearchResponse::SearchResult

      attr_reader :client, :provider

      def initialize(provider:, client:, cache: Rails.cache, expires_in: CACHE_TTL)
        @provider = provider.to_s
        @client = client
        @cache = cache
        @expires_in = expires_in
      end

      def search(query:, num: 10, location: "Germany", hl: "de", gl: "de", no_cache: false, **options)
        return uncached_search(query:, num:, location:, hl:, gl:, no_cache:, **options) if no_cache

        payload = cache.fetch(cache_key(query:, num:, location:, hl:, gl:, options:), expires_in: expires_in) do
          serialize_search_result(uncached_search(query:, num:, location:, hl:, gl:, no_cache:, **options))
        end

        deserialize_search_result(payload)
      end

      private

      attr_reader :cache, :expires_in

      def uncached_search(query:, num:, location:, hl:, gl:, no_cache:, **options)
        client.search(query:, num:, location:, hl:, gl:, no_cache:, **options)
      end

      def cache_key(query:, num:, location:, hl:, gl:, options:)
        [
          "llm_enrichment",
          "web_search",
          CACHE_VERSION,
          provider,
          normalized_query(query),
          normalized_cache_params(num:, location:, hl:, gl:, options:)
        ]
      end

      def normalized_query(query)
        query.to_s.squish
      end

      def normalized_cache_params(num:, location:, hl:, gl:, options:)
        {
          "num" => num.to_i,
          "location" => location.to_s,
          "hl" => hl.to_s,
          "gl" => gl.to_s,
          "options" => normalized_options(options)
        }
      end

      def normalized_options(options)
        options.to_h
          .transform_keys(&:to_s)
          .sort_by { |key, _value| key }
          .map { |key, value| [ key, normalized_option_value(value) ] }
      end

      def normalized_option_value(value)
        case value
        when Array
          value.map { |entry| normalized_option_value(entry) }
        when Hash
          value.transform_keys(&:to_s)
            .sort_by { |key, _entry_value| key }
            .to_h { |key, entry_value| [ key, normalized_option_value(entry_value) ] }
        else
          value.to_s
        end
      end

      def serialize_search_result(result)
        {
          "search_id" => result.search_id,
          "organic_results" => Array(result.organic_results).map { |organic_result| serialize_organic_result(organic_result) }
        }
      end

      def serialize_organic_result(organic_result)
        {
          "position" => organic_result.position,
          "link" => organic_result.link,
          "title" => organic_result.title,
          "displayed_link" => organic_result.displayed_link,
          "snippet" => organic_result.snippet,
          "source" => organic_result.source,
          "about_source_description" => organic_result.about_source_description,
          "languages" => Array(organic_result.languages),
          "regions" => Array(organic_result.regions)
        }
      end

      def deserialize_search_result(payload)
        normalized_payload = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}

        SearchResult.new(
          search_id: normalized_payload["search_id"],
          organic_results: Array(normalized_payload["organic_results"]).map do |organic_result_payload|
            deserialize_organic_result(organic_result_payload)
          end
        )
      end

      def deserialize_organic_result(payload)
        normalized_payload = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}

        OrganicResult.new(
          position: normalized_payload["position"],
          link: normalized_payload["link"],
          title: normalized_payload["title"],
          displayed_link: normalized_payload["displayed_link"],
          snippet: normalized_payload["snippet"],
          source: normalized_payload["source"],
          about_source_description: normalized_payload["about_source_description"],
          languages: Array(normalized_payload["languages"]),
          regions: Array(normalized_payload["regions"])
        )
      end
    end
  end
end
