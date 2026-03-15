require "net/http"
require "timeout"
require "uri"

module Importing
  module Reservix
    class HttpClient
      OPEN_TIMEOUT_SECONDS = 10
      READ_TIMEOUT_SECONDS = 30
      REQUEST_TIMEOUT_SECONDS = 90

      def get(url, accept: "application/json", language: "de")
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = accept if accept.present?
        request["x-api-key"] = api_key
        request["x-api-output-format"] = accept
        request["x-language"] = language if language.present?

        response = Timeout.timeout(REQUEST_TIMEOUT_SECONDS) do
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: OPEN_TIMEOUT_SECONDS,
            read_timeout: READ_TIMEOUT_SECONDS
          ) do |http|
            http.request(request)
          end
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise RequestError, "Request failed for #{uri} with status #{response.code}"
        end

        response.body.to_s
      rescue Timeout::Error
        raise RequestError, "Request timed out for #{uri} after #{REQUEST_TIMEOUT_SECONDS} seconds"
      end

      private

      def api_key
        value = AppConfig.reservix_api_key.to_s.strip
        raise RequestError, "RESERVIX_API_KEY is missing" if value.blank?

        value
      end
    end
  end
end
