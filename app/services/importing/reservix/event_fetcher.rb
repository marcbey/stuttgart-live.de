require "json"
require "uri"

module Importing
  module Reservix
    class EventFetcher
      DEFAULT_BASE_URL = "https://api.reservix.de/1/sale/event".freeze
      CITY = "Stuttgart".freeze
      LIMIT = 200
      MIN_LIMIT = 3

      def initialize(http_client: HttpClient.new, base_url: ENV["RESERVIX_EVENTS_API"])
        @http_client = http_client
        @base_url = base_url.to_s.strip.presence || DEFAULT_BASE_URL
      end

      def fetch_pages(lastupdate: nil, heartbeat: nil)
        page = 0

        loop do
          heartbeat&.call
          payload = parse_payload(http_client.get(build_url(page: page, lastupdate: lastupdate)))
          heartbeat&.call
          events = Array(payload["data"]).filter_map { |entry| entry.is_a?(Hash) ? entry : nil }

          yield(
            events,
            page: Integer(payload["page"], exception: false) || page,
            total_items: Integer(payload["totalItems"], exception: false) || events.size,
            limit: Integer(payload["limit"], exception: false) || LIMIT,
            server_time: parse_timestamp(payload["tsServer"])
          )

          break if events.empty?

          total_items = Integer(payload["totalItems"], exception: false)
          current_limit = Integer(payload["limit"], exception: false) || LIMIT
          break if total_items.present? && ((page + 1) * current_limit) >= total_items
          break if events.size < current_limit

          page += 1
        end
      end

      private

      attr_reader :http_client, :base_url

      def build_url(page:, lastupdate:)
        uri = URI.parse(base_url)
        params = {
          "city" => CITY,
          "limit" => LIMIT,
          "page" => page
        }
        params["lastupdate"] = lastupdate if lastupdate.present?
        uri.query = URI.encode_www_form(params)
        uri.to_s
      end

      def parse_payload(raw_body)
        payload = JSON.parse(raw_body)
        raise ParsingError, "Expected JSON object response" unless payload.is_a?(Hash)

        error_message = payload["errorMessage"].to_s.strip
        if error_message.present?
          raise RequestError, error_message
        end

        payload
      rescue JSON::ParserError => e
        raise ParsingError, "Failed to parse Reservix response: #{e.message}"
      end

      def parse_timestamp(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        Time.zone.parse(raw)
      rescue ArgumentError
        nil
      end
    end
  end
end
