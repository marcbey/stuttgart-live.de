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
        city = first_present(
          dump_payload["loc_city"],
          dump_payload.dig("data", "location", "city")
        )
        venue_name = first_present(
          dump_payload["loc_name"],
          dump_payload["location_name"],
          dump_payload.dig("data", "location", "name")
        )

        raw_candidates = [
          city,
          venue_name,
          "#{city} #{venue_name}",
          "#{city}, #{venue_name}",
          "#{city} - #{venue_name}"
        ]

        normalize_values(raw_candidates)
      end

      def first_present(*values)
        values.map { |value| value.to_s.strip }.find(&:present?).to_s
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
