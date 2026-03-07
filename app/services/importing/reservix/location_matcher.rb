module Importing
  module Reservix
    class LocationMatcher
      def initialize(location_whitelist)
        @location_whitelist = normalize_values(location_whitelist)
      end

      def match?(event_payload)
        return true if @location_whitelist.empty?

        location_candidates(event_payload).any? do |candidate|
          @location_whitelist.any? do |allowed|
            candidate.include?(allowed) || allowed.include?(candidate)
          end
        end
      end

      private

      def location_candidates(event_payload)
        payload = event_payload.is_a?(Hash) ? event_payload.deep_stringify_keys : {}
        references = payload["references"].is_a?(Hash) ? payload["references"].deep_stringify_keys : {}

        venue = Array(references["venue"]).find { |entry| entry.is_a?(Hash) }&.deep_stringify_keys || {}
        location = Array(references["location"]).find { |entry| entry.is_a?(Hash) }&.deep_stringify_keys || {}

        raw_candidates = [
          venue["city"],
          venue["formatted"],
          venue["name"],
          location["formatted"],
          location["name"]
        ]

        normalize_values(raw_candidates)
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
    end
  end
end
