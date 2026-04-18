require "json"
require "net/http"
require "uri"

module Importing
  module LlmEnrichment
    class SerpApiClient
      ENDPOINT = "https://serpapi.com/search.json".freeze
      OPEN_TIMEOUT_SECONDS = 5
      READ_TIMEOUT_SECONDS = 20

      Error = Class.new(StandardError)
      OrganicResult = WebSearchResponse::OrganicResult
      SearchResult = WebSearchResponse::SearchResult

      def initialize(api_key: AppConfig.serpapi_api_key)
        @api_key = api_key.to_s.strip
      end

      def search(query:, num: 10, location: "Germany", hl: "de", gl: "de", no_cache: false)
        raise Error, "SERPAPI_API_KEY fehlt." if api_key.blank?
        raise Error, "Suchanfrage darf nicht leer sein." if query.to_s.strip.blank?

        uri = URI.parse(ENDPOINT)
        uri.query = URI.encode_www_form(
          api_key: api_key,
          engine: "google",
          output: "json",
          q: query,
          location: location,
          hl: hl,
          gl: gl,
          num: num,
          no_cache: no_cache
        )

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT_SECONDS,
          read_timeout: READ_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end

        payload = JSON.parse(response.body.to_s.presence || "{}")
        error_message = payload["error"].to_s.presence
        raise Error, error_message if error_message.present?
        raise Error, "SerpApi-Request fehlgeschlagen (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)

        SearchResult.new(
          search_id: payload.dig("search_metadata", "id"),
          organic_results: Array(payload["organic_results"]).map do |item|
            OrganicResult.new(
              position: item["position"].to_i,
              link: item["link"].to_s,
              title: item["title"].to_s,
              snippet: item["snippet"].to_s
            )
          end
        )
      rescue JSON::ParserError => e
        raise Error, "SerpApi liefert ungültiges JSON: #{e.message}"
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
        raise Error, "SerpApi-Request fehlgeschlagen: #{e.class}"
      end

      private

      attr_reader :api_key
    end
  end
end
