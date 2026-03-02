require "date"
require "digest"
require "uri"

module Importing
  module Eventim
    class PayloadProjection
      URL_PATTERN = URI::DEFAULT_PARSER.make_regexp(%w[http https]).freeze

      EVENT_ID_KEYS = %w[event_id eventid external_event_id externalid id show_id showid performanceid performance_id].freeze
      DATE_KEYS = %w[date start_date startdate start_datetime startdatetime start event_date eventdate event_time eventtime].freeze
      CITY_KEYS = %w[city stadt town ort municipality locationcity venuecity eventplace].freeze
      VENUE_KEYS = %w[venue venuename location hall place veranstaltungsort eventvenue].freeze
      TITLE_KEYS = %w[title name eventtitle event_name eventname showtitle].freeze
      ARTIST_KEYS = %w[artist artists performer performers band headliner subheadline sideartistnames].freeze
      TICKET_URL_KEYS = %w[ticket_url ticketurl deeplink bookingurl eventurl url link eventlink].freeze
      IMAGE_URL_KEYS = %w[image image_url imageurl picture poster image_large image_medium].freeze

      def initialize(feed_payload:)
        @feed_payload = (feed_payload || {}).deep_stringify_keys
        @top_level_index = build_top_level_index
        @deep_value_index = nil
      end

      def to_attributes
        external_event_id = first_value_for_keys(EVENT_ID_KEYS)
        concert_date = parse_concert_date
        return nil if external_event_id.blank? || concert_date.nil?

        city = first_value_for_keys(CITY_KEYS).presence || "Unbekannt"
        venue_name = first_value_for_keys(VENUE_KEYS).presence || "Unbekannte Venue"
        title = first_value_for_keys(TITLE_KEYS).presence || "Unbekanntes Event"
        artist_name = first_value_for_keys(ARTIST_KEYS).presence || title
        ticket_url = first_url_for_keys(TICKET_URL_KEYS)
        image_url = first_url_for_keys(IMAGE_URL_KEYS)

        {
          external_event_id: external_event_id,
          concert_date: concert_date,
          city: city,
          venue_name: venue_name,
          title: title,
          artist_name: artist_name,
          concert_date_label: format_concert_date(concert_date),
          venue_label: format_venue(city, venue_name),
          ticket_url: ticket_url,
          image_url: image_url,
          source_payload_hash: Digest::SHA256.hexdigest(@feed_payload.to_json)
        }
      end

      private

      def parse_concert_date
        values_for_keys(DATE_KEYS).each do |raw|
          begin
            return Date.parse(raw)
          rescue ArgumentError, TypeError
            next
          end
        end

        nil
      end

      def first_value_for_keys(keys)
        values_for_keys(keys).first.to_s
      end

      def first_url_for_keys(keys)
        values_for_keys(keys).each do |value|
          return value if value.match?(URL_PATTERN)
        end

        ""
      end

      def values_for_keys(keys)
        normalized_keys = keys.map { |key| normalize_key(key) }
        top_level_values = normalized_keys.flat_map { |key| Array(@top_level_index[key]) }.uniq
        return top_level_values if top_level_values.present?

        index = deep_value_index
        normalized_keys
          .flat_map { |key| Array(index[key]) }
          .map { |value| value.to_s.strip }
          .reject(&:blank?)
          .uniq
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

      def build_top_level_index
        values = Hash.new { |hash, key| hash[key] = [] }
        @feed_payload.each do |key, value|
          values[normalize_key(key)].concat(extract_scalar_values(value))
        end
        values.transform_values { |entries| entries.map(&:to_s).reject(&:blank?).uniq }
      end

      def deep_value_index
        return @deep_value_index unless @deep_value_index.nil?

        values = Hash.new { |hash, key| hash[key] = [] }
        collect_values_for_keys(@feed_payload, values)
        @deep_value_index = values.transform_values { |entries| entries.map(&:to_s).reject(&:blank?).uniq }
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
