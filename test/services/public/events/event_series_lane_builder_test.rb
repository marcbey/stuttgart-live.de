require "test_helper"

module Public
  module Events
    class EventSeriesLaneBuilderTest < ActiveSupport::TestCase
      test "returns nil when only one visible event belongs to the series" do
        series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
        visible_event = create_public_series_event!(
          slug: "lane-builder-visible",
          event_series: series,
          status: "published",
          published_at: 1.day.ago
        )
        create_public_series_event!(
          slug: "lane-builder-hidden",
          event_series: series,
          status: "needs_review",
          published_at: nil
        )

        lane = EventSeriesLaneBuilder.new(
          event: visible_event,
          relation: Event.published_live
        ).call

        assert_nil lane
      end

      test "returns the full lane when at least two visible events belong to the series" do
        series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
        first_event = create_public_series_event!(
          slug: "lane-builder-first",
          event_series: series,
          start_at: 1.day.from_now.change(hour: 20),
          status: "published",
          published_at: 1.day.ago
        )
        second_event = create_public_series_event!(
          slug: "lane-builder-second",
          event_series: series,
          start_at: 2.days.from_now.change(hour: 20),
          status: "published",
          published_at: 1.day.ago
        )

        lane = EventSeriesLaneBuilder.new(
          event: first_event,
          relation: Event.published_live
        ).call

        assert_not_nil lane
        assert_equal "Viva la Vida", lane.title
        assert_equal [ first_event.id, second_event.id ], lane.events.map(&:id)
      end

      test "includes published past events in the series lane" do
        series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
        past_event = create_public_series_event!(
          slug: "lane-builder-past",
          event_series: series,
          start_at: 2.days.ago.change(hour: 20),
          status: "published",
          published_at: 5.days.ago
        )
        future_event = create_public_series_event!(
          slug: "lane-builder-future",
          event_series: series,
          start_at: 2.days.from_now.change(hour: 20),
          status: "published",
          published_at: 1.day.ago
        )

        lane = EventSeriesLaneBuilder.new(
          event: future_event,
          relation: Event.published_live
        ).call

        assert_not_nil lane
        assert_equal [ past_event.id, future_event.id ], lane.events.map(&:id)
      end

      private

      def create_public_series_event!(slug:, event_series:, status:, published_at:, start_at: 5.days.from_now.change(hour: 20))
        Event.create!(
          slug: slug,
          source_fingerprint: "test::public::event-series-lane-builder::#{slug}",
          title: "A Tribute to Frida Kahlo",
          artist_name: "Viva la Vida",
          start_at: start_at,
          venue: "Im Wizemann",
          city: "Stuttgart",
          status: status,
          published_at: published_at,
          event_series: event_series,
          event_series_assignment: "manual",
          source_snapshot: {}
        )
      end
    end
  end
end
