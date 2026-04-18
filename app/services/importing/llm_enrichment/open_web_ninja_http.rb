require "json"
require "open3"

module Importing
  module LlmEnrichment
    module OpenWebNinjaHttp
      STATUS_MARKER = "__OPENWEBNINJA_HTTP_STATUS__".freeze

      private

      def perform_open_web_ninja_get_request(endpoint:, params:, error_prefix:)
        stdout, stderr, status = Open3.capture3(*build_curl_command(endpoint:, params:))

        unless status.success?
          message = stderr.to_s.strip.presence || "curl exit status #{status.exitstatus}"
          raise self.class::Error, "#{error_prefix} fehlgeschlagen: #{message}"
        end

        body, http_status = extract_curl_response(stdout.to_s)
        payload = JSON.parse(body.presence || "{}")
        error_message = payload["message"].to_s.presence ||
          payload.dig("error", "message").to_s.presence ||
          payload["error"].to_s.presence

        raise self.class::Error, error_message if error_message.present?
        raise self.class::Error, "#{error_prefix} fehlgeschlagen (HTTP #{http_status})." unless http_status.to_i.between?(200, 299)

        payload
      rescue JSON::ParserError => e
        raise self.class::Error, "#{error_prefix} liefert ungültiges JSON: #{e.message}"
      end

      def build_curl_command(endpoint:, params:)
        [
          "curl",
          "--silent",
          "--show-error",
          "--location",
          "--http2",
          "--get",
          "--connect-timeout",
          self.class::OPEN_TIMEOUT_SECONDS.to_s,
          "--max-time",
          (self.class::OPEN_TIMEOUT_SECONDS + self.class::READ_TIMEOUT_SECONDS).to_s,
          "--header",
          "Accept: application/json",
          "--header",
          "X-API-Key: #{api_key}",
          "--write-out",
          "\n#{STATUS_MARKER}:%{http_code}",
          endpoint,
          *params.flat_map { |key, value| [ "--data-urlencode", "#{key}=#{value}" ] }
        ]
      end

      def extract_curl_response(output)
        body, separator, status_line = output.rpartition("\n#{STATUS_MARKER}:")
        raise self.class::Error, "OpenWebNinja-Antwort enthält keinen HTTP-Status." if separator.blank?

        [ body, status_line.to_s.strip ]
      end
    end
  end
end
