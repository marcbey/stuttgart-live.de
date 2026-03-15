require "net/http"
require "timeout"
require "uri"

module Importing
  module Eventim
    class HttpClient
      OPEN_TIMEOUT_SECONDS = 10
      READ_TIMEOUT_SECONDS = 30
      REQUEST_TIMEOUT_SECONDS = 90

      def get(url, accept: nil)
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = accept if accept.present?

        apply_basic_auth!(request)

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

      def apply_basic_auth!(request)
        user = AppConfig.eventim_user.to_s
        pass = AppConfig.eventim_pass.to_s
        raise RequestError, "EVENTIM_USER or EVENTIM_PASS is missing" if user.blank? || pass.blank?

        request.basic_auth(user, pass)
      end
    end
  end
end
