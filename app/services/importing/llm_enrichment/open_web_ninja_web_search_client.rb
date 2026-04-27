require "json"
require "net/http"
require "uri"

module Importing
  module LlmEnrichment
    class OpenWebNinjaWebSearchClient
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

        uri = URI.parse(ENDPOINT)
        uri.query = URI.encode_www_form(
          q: query,
          num: num,
          location: location,
          hl: hl,
          gl: gl
        )

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["X-API-Key"] = api_key

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
        error_message = api_error_message(payload)
        raise Error, error_message if error_message.present?
        raise Error, "OpenWebNinja-Websuche fehlgeschlagen (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)

        SearchResult.new(
          search_id: payload["request_id"],
          organic_results: Array(organic_results_payload(payload)).map do |item|
            OrganicResult.new(
              position: item["position"].to_i.nonzero? || item["rank"].to_i,
              link: (item["url"].presence || item["link"]).to_s,
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
      rescue JSON::ParserError => e
        raise Error, "OpenWebNinja-Websuche liefert ungültiges JSON: #{e.message}"
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
        raise Error, "OpenWebNinja-Websuche fehlgeschlagen: #{e.class}"
      end

      private

      attr_reader :api_key

      def organic_results_payload(payload)
        payload["organic_results"] || payload.dig("data", "organic_results")
      end

      def api_error_message(payload)
        error_payload = payload["error"]

        payload["message"].to_s.presence ||
          (error_payload.is_a?(Hash) ? error_payload["message"].to_s.presence : nil) ||
          error_payload.to_s.presence
      end
    end
  end
end
