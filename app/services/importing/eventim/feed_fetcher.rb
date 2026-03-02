require "nokogiri"
require "tempfile"
require "zlib"

module Importing
  module Eventim
    class FeedFetcher
      EVENT_NODE_KEYS = %w[event performance show item].freeze

      def initialize(http_client: HttpClient.new, feed_url: ENV["FEED_URL"])
        @http_client = http_client
        @feed_url = feed_url.to_s.strip
      end

      def fetch_events
        raise Error, "FEED_URL is not configured" if @feed_url.blank?

        body = @http_client.get(@feed_url, accept: "application/xml,text/xml")
        with_xml_file(body) do |xml_path|
          status_info_error = extract_status_info_error_from_xml(xml_path)
          raise RequestError, status_info_error if status_info_error.present?

          if block_given?
            parse_event_nodes_from_xml(xml_path) { |row| yield row }
            []
          else
            parse_event_nodes_from_xml(xml_path)
          end
        end
      rescue RequestError
        raise
      rescue StandardError => e
        raise ParsingError, "Could not parse Eventim XML feed: #{e.message}"
      end

      private

      def with_xml_file(body)
        source_tmp = Tempfile.new([ "eventim-source", ".bin" ])
        source_tmp.binmode
        source_tmp.write(body.to_s.dup.force_encoding(Encoding::BINARY))
        source_tmp.flush

        xml_tmp = Tempfile.new([ "eventim-feed", ".xml" ])
        xml_tmp.binmode

        if gzip_payload?(source_tmp.path)
          Zlib::GzipReader.open(source_tmp.path) do |gz|
            IO.copy_stream(gz, xml_tmp)
          end
        else
          source_tmp.rewind
          IO.copy_stream(source_tmp, xml_tmp)
        end
        xml_tmp.flush

        yield xml_tmp.path
      ensure
        source_tmp&.close!
        xml_tmp&.close!
      end

      def parse_event_nodes_from_xml(xml_path)
        rows = []
        File.open(xml_path, "rb") do |file|
          reader = Nokogiri::XML::Reader(file, nil, "UTF-8")

          reader.each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

            node_name = node.name.to_s.downcase
            next unless EVENT_NODE_KEYS.include?(node_name)

            payload = fast_xml_node_to_hash(node.outer_xml)
            next unless payload.is_a?(Hash) && payload.present?

            normalized_payload = payload.deep_stringify_keys
            if block_given?
              yield normalized_payload
            else
              rows << normalized_payload
            end
          end
        end

        rows
      end

      def fast_xml_node_to_hash(node_xml)
        root = Nokogiri::XML(node_xml).root
        return {} if root.nil?

        payload = {}
        root.element_children.each do |child|
          merge_value!(payload, child.name, node_value(child))
        end
        payload
      end

      def extract_status_info_error_from_xml(xml_path)
        File.open(xml_path, "rb") do |file|
          reader = Nokogiri::XML::Reader(file, nil, "UTF-8")

          reader.each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            next unless normalize_key(node.name) == "statusinfo"

            return extract_status_info_error(fast_xml_node_to_hash(node.outer_xml))
          end
        end

        ""
      end

      def node_value(node)
        children = node.element_children
        return blank_to_nil(node.text) if children.empty?

        value = {}
        children.each do |child|
          merge_value!(value, child.name, node_value(child))
        end
        value
      end

      def merge_value!(target, key, value)
        if target.key?(key)
          target[key] = Array(target[key]) << value
        else
          target[key] = value
        end
      end

      def blank_to_nil(text)
        value = text.to_s.strip
        value.present? ? value : nil
      end

      def gzip_payload?(path)
        file = File.open(path, "rb")
        signature = file.read(2)
        signature == "\x1f\x8b".b
      ensure
        file&.close
      end

      def extract_status_info_error(payload)
        return "" unless payload.is_a?(Hash)

        status_info =
          if payload.key?("code") || payload.key?("description") || payload.key?("reasonPhrase")
            payload
          else
            payload["StatusInfo"] || payload["statusInfo"] || payload["statusinfo"]
          end
        return "" unless status_info.is_a?(Hash)

        code = status_info["code"].to_s.strip
        return "" if code.blank? || code == "200"

        message = status_info["description"].to_s.strip
        message = status_info["reasonPhrase"].to_s.strip if message.blank?
        message = "Eventim feed returned status code #{code}" if message.blank?

        "#{message} (code #{code})"
      end

      def normalize_key(value)
        I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, "")
      end
    end
  end
end
