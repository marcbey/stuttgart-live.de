module Importing
  module Easyticket
    class LocationMatcher
      def initialize(location_whitelist)
        @location_whitelist = normalize_values(location_whitelist)
      end

      def match?(dump_payload)
        return true if @location_whitelist.empty?

        location_candidates(dump_payload).any? do |candidate|
          @location_whitelist.any? do |allowed|
            candidate.include?(allowed) || allowed.include?(candidate)
          end
        end
      end

      private

      def location_candidates(dump_payload)
        city = dump_payload["loc_city"].to_s
        venue_name = dump_payload["loc_name"].to_s

        raw_candidates = [
          city,
          venue_name,
          "#{city} #{venue_name}",
          "#{city}, #{venue_name}",
          "#{city} - #{venue_name}"
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
