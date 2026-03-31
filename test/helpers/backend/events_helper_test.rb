require "test_helper"

class Backend::EventsHelperTest < ActionView::TestCase
  include Backend::EventsHelper

  test "event_display_status_label shows planned label for future ready_for_publish events" do
    event = events(:needs_review_one)
    event.status = "ready_for_publish"
    event.published_at = 2.hours.from_now

    assert_equal "Unpublished/Geplant", event_display_status_label(event)
    assert_equal "status-badge status-badge-ready", event_display_status_badge_class(event)
  end
end
