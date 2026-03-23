module Importing
  class EventSeriesReference
    Result = Data.define(:source_type, :source_key, :name)

    class << self
      def from_payload(source_type:, payload:)
        normalized_payload = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}

        case source_type.to_s
        when "eventim"
          eventim_reference(normalized_payload)
        when "reservix"
          reservix_reference(normalized_payload)
        end
      end

      private

      def eventim_reference(payload)
        source_key = payload["esid"].to_s.strip.presence
        return if source_key.blank?

        Result.new(
          source_type: "eventim",
          source_key: source_key,
          name: payload["esname"].to_s.strip.presence || payload["eventname"].to_s.strip.presence
        )
      end

      def reservix_reference(payload)
        references = payload["references"].is_a?(Hash) ? payload["references"].deep_stringify_keys : {}
        group = Array(references["eventgroup"]).find { |entry| entry.is_a?(Hash) }&.deep_stringify_keys || {}
        source_key = group["id"].to_s.strip.presence
        return if source_key.blank?

        Result.new(
          source_type: "reservix",
          source_key: source_key,
          name: group["name"].to_s.strip.presence
        )
      end
    end
  end
end
