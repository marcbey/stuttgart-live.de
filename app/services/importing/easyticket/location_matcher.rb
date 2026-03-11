module Importing
  module Easyticket
    class LocationMatcher
      include Importing::LocationMatcherSupport

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
    end
  end
end
