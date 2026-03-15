require "json"
require "uri"
require "cgi"

module Importing
  module Easyticket
    class DumpFetcher
      DEFAULT_PAGE_SIZE = 100

      def initialize(http_client: HttpClient.new, events_api_url: AppConfig.easyticket_events_api)
        @http_client = http_client
        @events_api_url = events_api_url.to_s
      end

      def fetch_events
        raise Error, "EASYTICKET_EVENTS_API is not configured" if events_api_urls.empty?

        events_api_urls.flat_map { |url| fetch_events_for_url(url) }
      end

      private

      def events_api_urls
        @events_api_url
          .split(",")
          .map(&:strip)
          .reject(&:blank?)
      end

      def fetch_events_for_url(url)
        first_page_url = url_for_page(url, 1)
        parsed = fetch_and_parse(first_page_url)
        events = parsed.fetch(:events)
        last_page = parsed.fetch(:last_page)
        return events if last_page <= 1

        (2..last_page).each_with_object(events.dup) do |page, all_events|
          all_events.concat(fetch_and_parse(url_for_page(url, page)).fetch(:events))
        end
      end

      def fetch_and_parse(url)
        body = @http_client.get(url, accept: "application/json")
        parse_events(body)
      end

      def parse_events(body)
        parsed = parse_dump(body)
        image_index = extract_images_index(parsed)
        event_index = extract_event_index(parsed)
        location_index = extract_location_index(parsed)

        {
          events: extract_event_nodes(parsed)
            .map { |row| decorate_event(row, image_index, event_index, location_index) }
            .compact,
          last_page: extract_last_page(parsed)
        }
      rescue StandardError => e
        raise ParsingError, "Could not parse Easyticket events API payload: #{e.message}"
      end

      def extract_event_nodes(node)
        case node
        when Hash
          if node.key?("event_dates")
            Array(node["event_dates"]).select { |entry| entry.is_a?(Hash) }
          elsif node.key?("event")
            Array(node["event"]).select { |entry| entry.is_a?(Hash) }
          else
            node.values.flat_map { |value| extract_event_nodes(value) }
          end
        when Array
          node.flat_map { |value| extract_event_nodes(value) }
        else
          []
        end
      end

      def parse_dump(body)
        JSON.parse(body.to_s)
      end

      def decorate_event(row, image_index, event_index, location_index)
        return nil unless row.is_a?(Hash)

        event_payload = row.deep_stringify_keys
        event_id = event_payload["event_id"].to_s.strip
        location_id = event_payload["showsoft_location_id"].to_s.strip
        payload_data = event_payload["data"].is_a?(Hash) ? event_payload["data"].deep_stringify_keys : {}

        if event_id.present?
          event_images = image_index[event_id]
          payload_data["images"] = { event_id => event_images } if event_images.present?

          event_data = event_index[event_id]
          payload_data["event"] = event_data if event_data.present?
        end

        if location_id.present?
          location_data = location_index[location_id]
          payload_data["location"] = location_data if location_data.present?
        end

        return event_payload if payload_data.empty?

        event_payload.merge("data" => payload_data)
      end

      def extract_images_index(node)
        raw_index = find_images_index(node)
        return {} unless raw_index.is_a?(Hash)

        raw_index.each_with_object({}) do |(event_id, images), normalized_index|
          normalized_index[event_id.to_s] = deep_stringify(images)
        end
      end

      def find_images_index(node)
        case node
        when Hash
          images = node["images"]
          return images if event_image_index?(images)

          images = node["Images"]
          return images if event_image_index?(images)

          node.each_value do |value|
            nested_images = find_images_index(value)
            return nested_images if nested_images.present?
          end

          nil
        when Array
          node.each do |value|
            nested_images = find_images_index(value)
            return nested_images if nested_images.present?
          end

          nil
        end
      end

      def extract_event_index(node)
        raw_index = find_index_hash(node, "events")
        return {} unless raw_index.is_a?(Hash)

        raw_index.each_with_object({}) do |(event_id, event_payload), normalized_index|
          normalized_index[event_id.to_s] = deep_stringify(event_payload)
        end
      end

      def extract_location_index(node)
        raw_locations = find_locations(node)

        case raw_locations
        when Hash
          raw_locations.each_with_object({}) do |(location_id, location_payload), normalized_index|
            normalized_index[location_id.to_s] = deep_stringify(location_payload)
          end
        when Array
          raw_locations.each_with_object({}) do |location_payload, normalized_index|
            next unless location_payload.is_a?(Hash)

            location_id = location_payload["id"] || location_payload[:id]
            next if location_id.blank?

            normalized_index[location_id.to_s] = deep_stringify(location_payload)
          end
        else
          {}
        end
      end

      def find_index_hash(node, key_name)
        case node
        when Hash
          value = node[key_name]
          return value if event_image_index?(value)

          node.each_value do |nested_value|
            nested_index = find_index_hash(nested_value, key_name)
            return nested_index if nested_index.present?
          end

          nil
        when Array
          node.each do |nested_value|
            nested_index = find_index_hash(nested_value, key_name)
            return nested_index if nested_index.present?
          end

          nil
        end
      end

      def find_locations(node)
        case node
        when Hash
          locations = node["locations"]
          return locations if locations.is_a?(Array) || event_image_index?(locations)

          node.each_value do |nested_value|
            nested_locations = find_locations(nested_value)
            return nested_locations if nested_locations.present?
          end

          nil
        when Array
          node.each do |nested_value|
            nested_locations = find_locations(nested_value)
            return nested_locations if nested_locations.present?
          end

          nil
        end
      end

      def deep_stringify(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), result|
            result[key.to_s] = deep_stringify(nested_value)
          end
        when Array
          value.map { |nested_value| deep_stringify(nested_value) }
        else
          value
        end
      end

      def event_image_index?(value)
        return false unless value.is_a?(Hash)
        return false if value.empty?

        value.keys.all? { |key| key.to_s.match?(/\A\d+\z/) }
      end

      def extract_last_page(node)
        return 1 unless node.is_a?(Hash)

        raw_last_page = node["last_page"] || node.dig("data", "last_page")
        value = raw_last_page.to_i
        value.positive? ? value : 1
      end

      def url_for_page(url, page)
        uri = URI.parse(url)
        params = CGI.parse(uri.query.to_s)
        params["page"] = [ page.to_s ]
        params["pageSize"] = [ DEFAULT_PAGE_SIZE.to_s ] if params["pageSize"].blank?
        uri.query = URI.encode_www_form(params.sort_by { |key, _| key })
        uri.to_s
      end
    end
  end
end
