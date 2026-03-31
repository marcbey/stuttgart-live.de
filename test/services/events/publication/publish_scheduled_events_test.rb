require "test_helper"

class Events::Publication::PublishScheduledEventsTest < ActiveSupport::TestCase
  test "publishes due ready_for_publish events that are complete" do
    published_at = 2.hours.ago.change(usec: 0)
    event = build_scheduled_event(
      slug: "scheduled-publication-ready",
      source_fingerprint: "test::scheduled::ready",
      published_at: 2.hours.from_now.change(usec: 0)
    )
    event.update_columns(published_at: published_at)

    result = Events::Publication::PublishScheduledEvents.call(scope: Event.where(id: event.id))

    assert_equal 1, result.processed_count
    assert_equal 1, result.published_count
    assert_equal 0, result.skipped_count
    assert_equal "published", event.reload.status
    assert_equal true, event.auto_published
    assert_equal published_at, event.published_at.change(usec: 0)
  end

  test "keeps due ready_for_publish events unpublished when completeness is missing" do
    event = Event.create!(
      slug: "scheduled-publication-incomplete",
      source_fingerprint: "test::scheduled::incomplete",
      title: "Incomplete Scheduled Event",
      artist_name: "Incomplete Artist",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "ready_for_publish",
      published_at: 2.hours.from_now.change(usec: 0)
    )
    event.update_columns(published_at: 1.hour.ago.change(usec: 0))

    result = Events::Publication::PublishScheduledEvents.call(scope: Event.where(id: event.id))

    assert_equal 1, result.processed_count
    assert_equal 0, result.published_count
    assert_equal 1, result.skipped_count
    assert_equal "ready_for_publish", event.reload.status
    assert_includes event.completeness_flags, "missing_image"
  end

  private

  def build_scheduled_event(slug:, source_fingerprint:, published_at:)
    event = Event.create!(
      slug: slug,
      source_fingerprint: source_fingerprint,
      title: "Scheduled Event",
      artist_name: "Scheduled Artist",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "ready_for_publish",
      published_at: published_at
    )
    event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://tickets.example/scheduled",
      sold_out: false,
      priority_rank: 0
    )
    event.event_images.create!(purpose: EventImage::PURPOSE_DETAIL_HERO, file: png_upload)
    event
  end
end
