module Importing
  module LlmEnrichment
    class CachingWebSearchClient
      CACHE_VERSION = "v1".freeze
      CACHE_TTL = 1.week
      OrganicResult = WebSearchResponse::OrganicResult
      SearchResult = WebSearchResponse::SearchResult

      attr_reader :client, :provider

      def initialize(provider:, client:, cache: Rails.cache, expires_in: CACHE_TTL, api_call_recorder: nil)
        @provider = provider.to_s
        @client = client
        @cache = cache
        @expires_in = expires_in
        @api_call_recorder = api_call_recorder
      end

      def search(query:, num: 10, location: "Germany", hl: "de", gl: "de", no_cache: false, audit_context: {}, **options)
        return recorded_uncached_search(query:, num:, location:, hl:, gl:, no_cache:, audit_context:, options:) if no_cache

        key = cache_key(query:, num:, location:, hl:, gl:, options:)
        cached_payload = cache.read(key)
        if cached_payload.present?
          record_api_call!(
            query:,
            num:,
            location:,
            hl:,
            gl:,
            audit_context:,
            options:,
            cached: true,
            status: "succeeded",
            response_payload: response_payload_for(cached_payload)
          )
          return deserialize_search_result(cached_payload)
        end

        result = recorded_uncached_search(query:, num:, location:, hl:, gl:, no_cache:, audit_context:, options:)
        payload = serialize_search_result(result)
        cache.write(key, payload, expires_in: expires_in)
        deserialize_search_result(payload)
      end

      private

      attr_reader :api_call_recorder, :cache, :expires_in

      def uncached_search(query:, num:, location:, hl:, gl:, no_cache:, **options)
        client.search(query:, num:, location:, hl:, gl:, no_cache:, **options)
      end

      def recorded_uncached_search(query:, num:, location:, hl:, gl:, no_cache:, audit_context:, options:)
        started_at = Time.current
        result = uncached_search(query:, num:, location:, hl:, gl:, no_cache:, **options)
        finished_at = Time.current
        record_api_call!(
          query:,
          num:,
          location:,
          hl:,
          gl:,
          audit_context:,
          options:,
          cached: false,
          status: "succeeded",
          started_at:,
          finished_at:,
          response_payload: response_payload_for(serialize_search_result(result))
        )
        result
      rescue StandardError => e
        finished_at = Time.current
        record_api_call!(
          query:,
          num:,
          location:,
          hl:,
          gl:,
          audit_context:,
          options:,
          cached: false,
          status: "failed",
          started_at:,
          finished_at:,
          error_class: e.class.to_s,
          error_message: e.message
        )
        raise
      end

      def record_api_call!(
        query:,
        num:,
        location:,
        hl:,
        gl:,
        audit_context:,
        options:,
        cached:,
        status:,
        started_at: nil,
        finished_at: nil,
        response_payload: {},
        error_class: nil,
        error_message: nil
      )
        return if api_call_recorder.blank?

        started_at ||= Time.current
        finished_at ||= started_at
        request_payload = {
          query: query,
          num: num,
          location: location,
          hl: hl,
          gl: gl
        }.merge(audit_context.to_h).merge(options.to_h)

        api_call_recorder.record(
          provider: provider,
          operation: "web_search",
          status: status,
          cached: cached,
          event_id: audit_context.to_h[:event_id] || audit_context.to_h["event_id"],
          started_at: started_at,
          finished_at: finished_at,
          duration_ms: duration_ms(started_at, finished_at),
          request_payload: request_payload,
          response_payload: response_payload,
          error_class: error_class,
          error_message: error_message
        )
      end

      def response_payload_for(payload)
        normalized_payload = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}

        {
          search_id: normalized_payload["search_id"],
          organic_results_count: Array(normalized_payload["organic_results"]).size
        }
      end

      def duration_ms(started_at, finished_at)
        ((finished_at - started_at) * 1000).round
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
