module Public
  module Events
    class EventSeriesLaneBuilder
      Lane = Data.define(:series, :title, :events)

      def initialize(event:, relation:, exclude_event: nil, limit: nil)
        @event = event
        @relation = relation
        @exclude_event = exclude_event
        @limit = limit
      end

      def call
        return if event.event_series.blank?

        events =
          relation
            .where(event_series_id: event.event_series_id)
            .where(status: "published")
            .where("published_at IS NULL OR published_at <= ?", Time.current)
            .where("start_at >= ?", Time.zone.today.beginning_of_day)
            .reorder(:start_at, :id)
            .to_a
        return if events.size < 2

        events = events.reject { |series_event| series_event.id == exclude_event.id } if exclude_event.present?

        Lane.new(
          series: event.event_series,
          title: event.event_series.name.to_s.strip.presence || event.event_series.display_name,
          events: limit.present? ? events.first(limit) : events
        )
      end

      private

      attr_reader :event, :exclude_event, :limit, :relation
    end
  end
end
