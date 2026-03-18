require "bigdecimal"
require "date"
require "digest"
require "set"

module Importing
  module Reservix
    class PayloadProjection
      DOORS_TIME_KEYS = %w[doors doorsat doors_at doorsopen doors_open entrytime entry_time].freeze

      def initialize(event_payload:)
        @event_payload = (event_payload || {}).deep_stringify_keys
        @references = @event_payload["references"].is_a?(Hash) ? @event_payload["references"].deep_stringify_keys : {}
      end

      def to_attributes
        external_event_id = @event_payload["id"].to_s.strip
        concert_date = parse_concert_date
        return nil if external_event_id.blank? || concert_date.nil?

        title = @event_payload["name"].to_s.strip.presence || "Unbekanntes Event"
        artist_name = @event_payload["artist"].to_s.strip.presence || title
        city = venue_reference["city"].to_s.strip.presence || location_city_fallback
        venue_name = extract_venue_name.presence || "Unbekannte Venue"
        doors_time = first_value_for_keys(DOORS_TIME_KEYS).presence

        min_price = parse_decimal(@event_payload["minPrice"])
        max_price = parse_decimal(@event_payload["maxPrice"])
        min_price ||= max_price
        max_price ||= min_price

        {
          external_event_id: external_event_id,
          concert_date: concert_date,
          city: city,
          venue_name: venue_name,
          title: title,
          artist_name: artist_name,
          doors_time: doors_time,
          min_price: min_price,
          max_price: max_price,
          concert_date_label: format_concert_date(concert_date),
          venue_label: format_venue(city, venue_name),
          ticket_url: ticket_url,
          source_payload_hash: Digest::SHA256.hexdigest(@event_payload.to_json)
        }
      end

      def image_candidates
        candidates = []
        seen = Set.new

        Array(@references["image"]).each do |entry|
          image = entry.is_a?(Hash) ? entry.deep_stringify_keys : {}
          next if ActiveModel::Type::Boolean.new.cast(image["isPlaceholder"])

          type = Integer(image["type"], exception: false)
          image_type =
            case type
            when 1 then "detail"
            when 2 then "slideshow"
            else "image"
            end
          role =
            case type
            when 1 then "cover"
            when 2 then "gallery"
            else "gallery"
            end

          [
            [ image["url"], image_type, role ],
            [ image["thumbnail_url"], "#{image_type}_thumbnail", "thumb" ]
          ].each do |url, candidate_type, candidate_role|
            normalized_url = ImportEventImage.normalize_image_url(url)
            next if normalized_url.blank?

            key = [ candidate_type, normalized_url.downcase ]
            next if seen.include?(key)

            seen << key
            candidates << {
              image_type: candidate_type,
              image_url: normalized_url,
              role: candidate_role,
              position: candidates.length
            }
          end
        end

        candidates
      end

      def bookable?
        ActiveModel::Type::Boolean.new.cast(@event_payload["bookable"])
      end

      def modified_at
        raw = @event_payload["modified"].to_s.strip
        return nil if raw.blank?

        Time.zone.parse(raw)
      rescue ArgumentError
        nil
      end

      private

      def parse_concert_date
        raw = @event_payload["startdate"].to_s.strip
        return nil if raw.blank?

        Date.parse(raw)
      rescue ArgumentError
        nil
      end

      def parse_decimal(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        BigDecimal(raw)
      rescue ArgumentError
        nil
      end

      def ticket_url
        @event_payload["affiliateSaleUrl"].to_s.strip.presence ||
          @event_payload["canonicalUrl"].to_s.strip.presence ||
          @event_payload["publicSaleUrl"].to_s.strip.presence
      end

      def extract_venue_name
        location_reference["name"].to_s.strip.presence ||
          venue_reference["name"].to_s.strip.presence ||
          formatted_name_prefix(location_reference["formatted"]) ||
          formatted_name_prefix(venue_reference["formatted"])
      end

      def location_city_fallback
        formatted = location_reference["formatted"].to_s.strip
        return nil if formatted.blank?

        formatted.split(",").last.to_s.strip.split(/\s+/, 2).last.to_s.strip.presence
      end

      def formatted_name_prefix(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        raw.split(" - ").first.to_s.strip.presence
      end

      def event_reference(key)
        Array(@references[key]).find { |entry| entry.is_a?(Hash) }&.deep_stringify_keys || {}
      end

      def first_value_for_keys(keys)
        values_for_keys(keys).first.to_s
      end

      def values_for_keys(keys)
        normalized_keys = keys.map { |key| normalize_key(key) }
        index = deep_value_index

        normalized_keys
          .flat_map { |key| Array(index[key]) }
          .map { |value| value.to_s.strip }
          .reject(&:blank?)
          .uniq
      end

      def deep_value_index
        return @deep_value_index unless @deep_value_index.nil?

        values = Hash.new { |hash, key| hash[key] = [] }
        collect_values_for_keys(@event_payload, values)
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

      def location_reference
        @location_reference ||= event_reference("location")
      end

      def venue_reference
        @venue_reference ||= event_reference("venue")
      end

      def format_concert_date(date)
        "#{date.day}.#{date.month}.#{date.year}"
      end

      def format_venue(city, venue_name)
        [ city, venue_name ].reject(&:blank?).join(", ")
      end

      def normalize_key(value)
        I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, "")
      end
    end
  end
end
