require "active_support/core_ext/hash/conversions"

module Importing
  module Easyticket
    class DumpFetcher
      def initialize(http_client: HttpClient.new, xmp_dump_url: ENV["XMP_DUMP_URL"])
        @http_client = http_client
        @xmp_dump_url = xmp_dump_url.to_s
      end

      def fetch_events
        raise Error, "XMP_DUMP_URL is not configured" if dump_urls.empty?

        dump_urls.flat_map do |url|
          body = @http_client.get(url, accept: "application/xml,text/xml")
          parse_xml_events(body)
        end
      end

      private

      def dump_urls
        @xmp_dump_url
          .split(",")
          .map(&:strip)
          .reject(&:blank?)
      end

      def parse_xml_events(xml_body)
        parsed = Hash.from_xml(xml_body)
        extract_event_nodes(parsed)
          .map { |row| row.is_a?(Hash) ? row.deep_stringify_keys : nil }
          .compact
      rescue StandardError => e
        raise ParsingError, "Could not parse Easyticket XML dump: #{e.message}"
      end

      def extract_event_nodes(node)
        case node
        when Hash
          if node.key?("event")
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
    end
  end
end
