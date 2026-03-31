module Public
  module Events
    class EventSeriesLaneBuilder
      Lane = Data.define(:series, :title, :events)

      def initialize(event:, relation:)
        @event = event
        @relation = relation
      end

      def call
        return if event.event_series.blank?

        events =
          relation
            .where(event_series_id: event.event_series_id)
            .where(status: "published")
            .where("published_at IS NULL OR published_at <= ?", Time.current)
            .reorder(:start_at, :id)
            .to_a
        return if events.size < 2

        Lane.new(
          series: event.event_series,
          title: event.event_series.name.to_s.strip.presence || event.event_series.display_name,
          events: events
        )
      end

      private

      attr_reader :event, :relation
    end
  end
end
