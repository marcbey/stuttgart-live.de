module Importing
  module Eventim
    class TicketOfferClassifier
      Result = Data.define(:kind, :series_id, :series_name, :identity_key)

      AUXILIARY_PATTERNS = [
        /\bvip\b/i,
        /meet\s*&\s*greet/i,
        /\bpackage\b/i,
        /\bupgrade\b/i,
        /early\s+entry/i
      ].freeze

      def self.call(record)
        new(record).call
      end

      def initialize(record)
        @record = record
        @payload = record.raw_payload.is_a?(Hash) ? record.raw_payload.deep_stringify_keys : {}
      end

      def call
        Result.new(
          kind: auxiliary? ? "auxiliary" : "main",
          series_id: series_id,
          series_name: series_name,
          identity_key: identity_key
        )
      end

      private

      attr_reader :payload, :record

      def auxiliary?
        candidate_text = [
          record.title,
          record.artist_name,
          payload["eventname"],
          payload["name"],
          payload["title"],
          payload["eventtitle"]
        ].join(" ")

        AUXILIARY_PATTERNS.any? { |pattern| candidate_text.match?(pattern) }
      end

      def series_id
        payload["esid"].to_s.strip.presence
      end

      def series_name
        payload["esname"].to_s.strip.presence
      end

      def identity_key
        return nil if series_id.blank?
        return nil if record.start_at.blank?

        venue_key = normalize_venue(venue_for_identity)
        return nil if venue_key.blank?

        [ "eventim", series_id, record.start_at.iso8601, venue_key ]
      end

      def venue_for_identity
        Importing::Eventim::PayloadProjection::VENUE_KEYS.each do |key|
          value = payload[key].to_s.strip
          return value if value.present?
        end

        nil
      end

      def normalize_venue(value)
        I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip.presence
      end
    end
  end
end
