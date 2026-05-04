require "test_helper"

class Editorial::EventCompletenessCheckerTest < ActiveSupport::TestCase
  test "missing ticket url is reported but does not block publication readiness" do
    event = Event.create!(
      slug: "complete-without-ticket-url",
      source_fingerprint: "test::complete-without-ticket-url",
      title: "Event ohne Ticket-URL",
      artist_name: "Ticketlose Band",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )
    event.event_images.create!(purpose: EventImage::PURPOSE_DETAIL_HERO, file: png_upload)

    result = Editorial::EventCompletenessChecker.new(event: event).call

    assert_includes result.flags, "missing_ticket_url"
    assert_equal 86, result.score
    assert result.ready_for_publish?
  end
end
