module Importing
  module Reservix
    class LocationMatcher
      include Importing::LocationMatcherSupport

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
    end
  end
end
