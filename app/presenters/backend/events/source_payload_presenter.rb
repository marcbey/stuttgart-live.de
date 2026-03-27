module Backend
  module Events
    class SourcePayloadPresenter
      PayloadSource = Data.define(:source, :external_event_id, :payload) do
        def formatted_payload
          SourcePayloadPresenter.pretty_json(payload)
        end
      end

      def self.pretty_json(value)
        parsed =
          if value.is_a?(String)
            JSON.parse(value)
          else
            value
          end

        JSON.pretty_generate(parsed)
      rescue JSON::ParserError, JSON::GeneratorError
        value.to_s
      end

      def initialize(event)
        @event = event
      end

      def display_promoter
        event.promoter_name.to_s.strip.presence ||
          event.promoter_id.to_s.strip.presence
      end

      def payload_sources
        @payload_sources ||= begin
          sources = event.source_snapshot.is_a?(Hash) ? Array(event.source_snapshot["sources"]) : []

          sources.filter_map do |source|
            next unless source.is_a?(Hash)

            raw_payload = source["raw_payload"]
            next unless raw_payload.is_a?(Hash)

            PayloadSource.new(
              source: source["source"].to_s.presence || "unbekannt",
              external_event_id: source["external_event_id"].to_s.presence,
              payload: raw_payload || {}
            )
          end
        end
      end

      private

      attr_reader :event

      alias_method :display_promoter_id, :display_promoter
    end
  end
end
