require "test_helper"

class Public::EventsHelperTest < ActionView::TestCase
  include Public::EventsHelper

  test "public_event_ticket_price returns ab price for ranges" do
    event = events(:published_one)
    offer = event_offers(:published_one_offer)

    event.min_price = BigDecimal("35.96")
    event.max_price = BigDecimal("59.90")

    assert_equal "ab 35,96€", public_event_ticket_price(event, offer)
  end

  test "public_event_ticket_price falls back to offer text for single prices" do
    event = events(:published_one)
    offer = event_offers(:published_one_offer)

    event.min_price = BigDecimal("45")
    event.max_price = BigDecimal("45")

    assert_equal "45 EUR", public_event_ticket_price(event, offer)
  end

  test "public_event_visibility_badges labels scheduled published events as geplant" do
    event = events(:published_one)
    event.published_at = 2.hours.from_now

    assert_equal [ { label: "Geplant", css_class: "status-badge-published" } ], public_event_visibility_badges(event)
    assert_not public_frontend_visible?(event)
  end
end
