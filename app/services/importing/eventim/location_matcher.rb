require "set"

module Importing
  module Eventim
    class LocationMatcher
      CITY_KEYS = %w[
        city
        stadt
        town
        ort
        municipality
        locationcity
        venuecity
        eventplace
      ].freeze
      VENUE_KEYS = %w[
        venue
        venuename
        location
        hall
        place
        veranstaltungsort
        eventvenue
      ].freeze

      def initialize(location_whitelist)
        @location_whitelist = normalize_values(location_whitelist)
      end

      def match?(payload)
        return true if @location_whitelist.empty?

        location_candidates(payload).any? do |candidate|
          @location_whitelist.any? do |allowed|
            candidate.include?(allowed) || allowed.include?(candidate)
          end
        end
      end

      private

      def location_candidates(payload)
        city = first_value_for_keys(payload, CITY_KEYS)
        venue_name = first_value_for_keys(payload, VENUE_KEYS)

        raw_candidates = [
          city,
          venue_name,
          "#{city} #{venue_name}",
          "#{city}, #{venue_name}",
          "#{city} - #{venue_name}"
        ]

        normalize_values(raw_candidates)
      end

      def first_value_for_keys(payload, keys)
        values_for_keys(payload, keys).first.to_s
      end

      def values_for_keys(payload, keys)
        target_keys = keys.map { |key| normalize_key(key) }.to_set
        direct_values = extract_direct_values(payload, target_keys)
        normalized_direct_values = normalize_values(direct_values)
        return normalized_direct_values if normalized_direct_values.present?

        values = []
        collect_values_for_keys(payload, target_keys, values)
        normalize_values(values)
      end

      def extract_direct_values(payload, target_keys)
        return [] unless payload.is_a?(Hash)

        values = []
        payload.each do |key, value|
          next unless target_keys.include?(normalize_key(key))

          values.concat(extract_scalar_values(value))
        end
        values
      end

      def collect_values_for_keys(node, target_keys, values)
        case node
        when Hash
          node.each do |key, value|
            values.concat(extract_scalar_values(value)) if target_keys.include?(normalize_key(key))
            collect_values_for_keys(value, target_keys, values)
          end
        when Array
          node.each { |entry| collect_values_for_keys(entry, target_keys, values) }
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

      def normalize_values(values)
        Array(values)
          .map { |value| normalize(value.to_s) }
          .reject(&:blank?)
          .uniq
      end

      def normalize(value)
        I18n.transliterate(value)
          .downcase
          .gsub(/[^a-z0-9]+/, " ")
          .squeeze(" ")
          .strip
      end

      def normalize_key(value)
        I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, "")
      end
    end
  end
end
