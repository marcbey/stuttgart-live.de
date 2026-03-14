require "bigdecimal"
require "cgi"
require "set"
require "uri"

module Merging
  class SyncFromImports
    module RecordBuilders
      class Base
        URL_PATTERN = URI::DEFAULT_PARSER.make_regexp(%w[http https]).freeze

        def initialize(raw_event_import:)
          @raw_event_import = raw_event_import
          @payload = raw_event_import.payload.is_a?(Hash) ? raw_event_import.payload.deep_stringify_keys : {}
          @deep_value_index = nil
          @scalar_values = nil
        end

        def build
          return nil if source_identifier.blank? || external_event_id.blank? || start_at.blank?

          title_value = title.to_s.strip.presence || "Unbekanntes Event"
          artist_value = artist_name.to_s.strip.presence || title_value
          venue_value = venue.to_s.strip.presence || "Unbekannte Venue"

          ImportRecord.new(
            source: source,
            source_identifier: source_identifier,
            external_event_id: external_event_id,
            artist_name: artist_value,
            title: title_value,
            start_at: start_at,
            doors_at: doors_at,
            city: city.to_s.strip.presence,
            venue: venue_value,
            promoter_id: promoter_id.to_s.strip.presence,
            badge_text: badge_text.to_s.strip.presence,
            youtube_url: youtube_url.to_s.strip.presence,
            homepage_url: homepage_url.to_s.strip.presence,
            facebook_url: facebook_url.to_s.strip.presence,
            event_info: event_info.to_s.strip.presence,
            min_price: min_price,
            max_price: max_price,
            images: images,
            genre: normalized_genre(genre),
            ticket_url: ticket_url.to_s.strip.presence,
            ticket_price_text: ticket_price_text.to_s.strip.presence,
            raw_payload: payload
          )
        end

        private

        attr_reader :payload, :raw_event_import

        def source
          raw_event_import.import_event_type
        end

        def source_identifier
          raw_event_import.source_identifier.to_s.strip
        end

        def first_value_for_keys(keys)
          values_for_keys(keys).first.to_s.strip
        end

        def values_for_keys(keys)
          normalized_keys = Array(keys).map { |key| normalize_key(key) }
          index = deep_value_index

          normalized_keys
            .flat_map { |key| Array(index[key]) }
            .map { |value| value.to_s.strip }
            .reject(&:blank?)
            .uniq
        end

        def first_url_for_keys(keys)
          values_for_keys(keys).find { |value| value.match?(URL_PATTERN) }
        end

        def first_url_for_hosts(*hosts)
          scalar_values.find do |value|
            next false unless value.match?(URL_PATTERN)

            uri = URI.parse(value)
            host = uri.host.to_s.downcase
            hosts.any? { |candidate| host.include?(candidate) }
          rescue URI::InvalidURIError
            false
          end
        end

        def scalar_values
          return @scalar_values unless @scalar_values.nil?

          values = []
          collect_scalar_values(payload, values)
          @scalar_values = values.map { |value| value.to_s.strip }.reject(&:blank?).uniq
        end

        def collect_scalar_values(node, values)
          case node
          when Hash
            node.each_value { |value| collect_scalar_values(value, values) }
          when Array
            node.each { |entry| collect_scalar_values(entry, values) }
          when String, Numeric, TrueClass, FalseClass
            values << node
          end
        end

        def deep_value_index
          return @deep_value_index unless @deep_value_index.nil?

          values = Hash.new { |hash, key| hash[key] = [] }
          collect_values_for_keys(payload, values)
          @deep_value_index = values.transform_values { |entries| entries.map(&:to_s).reject(&:blank?).uniq }
        end

        def collect_values_for_keys(node, values)
          case node
          when Hash
            node.each do |key, value|
              values[normalize_key(key)].concat(extract_scalar_values(value))
              collect_values_for_keys(value, values)
            end
          when Array
            node.each { |entry| collect_values_for_keys(entry, values) }
          end
        end

        def extract_scalar_values(value)
          case value
          when String, Numeric, TrueClass, FalseClass
            [ value.to_s ]
          when Array
            value.flat_map { |entry| extract_scalar_values(entry) }
          else
            []
          end
        end

        def normalized_genre(value)
          raw_value = value.to_s.strip
          return nil if raw_value.blank?

          raw_value.split(/[;,]/).first.to_s.strip.presence
        end

        def parse_date(value)
          raw = value.to_s.strip
          return nil if raw.blank?

          Date.parse(raw)
        rescue ArgumentError
          nil
        end

        def parse_datetime(value)
          raw = value.to_s.strip
          return nil if raw.blank?

          Time.zone.parse(raw)
        rescue ArgumentError
          nil
        end

        def parse_time_from_datetime(value)
          parse_datetime(value)&.strftime("%H:%M")
        end

        def combine_date_and_time(date, time_value)
          return nil if date.nil?

          hour, minute = DuplicationKey.parse_time_components(time_value)
          Time.zone.local(date.year, date.month, date.day, hour, minute, 0)
        end

        def parse_decimal(value)
          raw = value.to_s.strip
          return nil if raw.blank?

          normalized = raw.gsub(/[^0-9,.\-]/, "")
          return nil if normalized.blank?

          if normalized.include?(",") && normalized.include?(".")
            if normalized.rindex(",") > normalized.rindex(".")
              normalized = normalized.delete(".").tr(",", ".")
            else
              normalized = normalized.delete(",")
            end
          elsif normalized.include?(",")
            normalized = normalized.tr(",", ".")
          end

          BigDecimal(normalized)
        rescue ArgumentError
          nil
        end

        def format_price_decimal(decimal_value)
          format("%.2f", decimal_value).tr(".", ",")
        end

        def format_price_range(min_price, max_price, currency: "EUR")
          min_decimal = normalize_decimal(min_price)
          max_decimal = normalize_decimal(max_price)
          return nil if min_decimal.nil? && max_decimal.nil?

          min_decimal ||= max_decimal
          max_decimal ||= min_decimal

          if min_decimal == max_decimal
            "#{format_price_decimal(min_decimal)} #{currency}"
          else
            "#{format_price_decimal(min_decimal)} - #{format_price_decimal(max_decimal)} #{currency}"
          end
        end

        def normalize_decimal(value)
          return value if value.is_a?(BigDecimal)

          parse_decimal(value)
        end

        def normalize_import_description(value)
          text = value.to_s
          return nil if text.strip.blank?

          normalized =
            CGI.unescapeHTML(text)
              .gsub(/<\s*br\s*\/?>/i, "\n")
              .gsub(/<\/p\s*>/i, "\n\n")
              .gsub(/<[^>]+>/, "")
              .gsub(/\r\n?/, "\n")
              .gsub(/[ \t]+\n/, "\n")
              .gsub(/\n{3,}/, "\n\n")
              .strip

          normalized.presence
        end

        def import_images_from_candidates(candidates)
          seen = Set.new

          Array(candidates).filter_map do |candidate|
            row = candidate.respond_to?(:to_h) ? candidate.to_h : {}
            image_url = ImportEventImage.normalize_image_url(row[:image_url] || row["image_url"])
            next if image_url.blank?

            source_value = (row[:source] || row["source"]).to_s.strip.presence || source
            image_type = (row[:image_type] || row["image_type"]).to_s.strip.presence || "image"
            key = [ source_value, image_type, image_url.downcase ]
            next if seen.include?(key)

            seen << key
            ImportImage.new(
              source: source_value,
              image_type: image_type,
              image_url: image_url,
              role: (row[:role] || row["role"]).to_s.strip.presence || ImportEventImage.derive_role(source: source_value, image_type: image_type),
              aspect_hint: (row[:aspect_hint] || row["aspect_hint"]).to_s.strip.presence || ImportEventImage.derive_aspect_hint(url: image_url, image_type: image_type),
              position: (row[:position] || row["position"]).to_i
            )
          end
        end

        def normalize_key(value)
          I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, "")
        end
      end
    end
  end
end
