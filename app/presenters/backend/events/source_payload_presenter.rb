module Backend
  module Events
    class SourcePayloadPresenter
      PayloadSource = Data.define(:source, :external_event_id, :dump_payload, :detail_payload) do
        def formatted_dump_payload
          SourcePayloadPresenter.pretty_json(dump_payload)
        end

        def formatted_detail_payload
          SourcePayloadPresenter.pretty_json(detail_payload)
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

      def display_promoter_id
        promoter_id = event.promoter_id.to_s.strip
        return promoter_id if promoter_id.present?

        payload_sources.each do |payload_source|
          next unless payload_source.source == "eventim"

          attributes = Importing::Eventim::PayloadProjection.new(feed_payload: payload_source.dump_payload).to_attributes
          candidate = attributes&.dig(:promoter_id).to_s.strip
          return candidate if candidate.present?
        end

        nil
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
              dump_payload: raw_payload["dump_payload"] || {},
              detail_payload: raw_payload["detail_payload"] || {}
            )
          end
        end
      end

      private

      attr_reader :event
    end
  end
end
