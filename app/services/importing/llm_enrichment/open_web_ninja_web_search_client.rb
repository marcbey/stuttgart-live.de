module Importing
  module LlmEnrichment
    class OpenWebNinjaWebSearchClient
      include OpenWebNinjaHttp

      ENDPOINT = "https://api.openwebninja.com/realtime-web-search/search".freeze
      OPEN_TIMEOUT_SECONDS = 5
      READ_TIMEOUT_SECONDS = 20

      Error = Class.new(StandardError)
      OrganicResult = WebSearchResponse::OrganicResult
      SearchResult = WebSearchResponse::SearchResult

      def initialize(api_key: AppConfig.openwebninja_api_key)
        @api_key = api_key.to_s.strip
      end

      def search(query:, num: 10, location: "Germany", hl: "de", gl: "de", **)
        raise Error, "OPENWEBNINJA_API_KEY fehlt." if api_key.blank?
        raise Error, "Suchanfrage darf nicht leer sein." if query.to_s.strip.blank?

        payload = perform_open_web_ninja_get_request(
          endpoint: ENDPOINT,
          params: {
          q: query,
          num: num,
          location: location,
          hl: hl,
          gl: gl
          },
          error_prefix: "OpenWebNinja-Websuche"
        )

        SearchResult.new(
          search_id: payload["request_id"],
          organic_results: Array(payload.dig("data", "organic_results")).map do |item|
            OrganicResult.new(
              position: item["position"].to_i.nonzero? || item["rank"].to_i,
              link: item["url"].to_s,
              title: item["title"].to_s,
              displayed_link: item["displayed_link"].to_s,
              snippet: item["snippet"].to_s,
              source: item["source"].to_s,
              about_source_description: item.dig("about_this_result", "source", "description").to_s,
              languages: Array(item.dig("about_this_result", "languages")).map(&:to_s),
              regions: Array(item.dig("about_this_result", "regions")).map(&:to_s)
            )
          end
        )
      end

      private

      attr_reader :api_key
    end
  end
end
