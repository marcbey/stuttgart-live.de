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

  test "public_event_ticket_price does not use a manual offer when an imported primary offer is sold out" do
    event = Event.create!(
      slug: "helper-public-ticket-price-imported-blocks-manual",
      source_fingerprint: "test::helper::public-ticket-price-imported-blocks-manual",
      title: "Helper Ticket Priority",
      artist_name: "Helper Artist",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-helper-1",
      ticket_url: "https://easyticket.example/helper",
      ticket_price_text: "49 EUR",
      sold_out: true,
      priority_rank: 0
    )

    event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/helper",
      ticket_price_text: "39 EUR",
      sold_out: false,
      priority_rank: 0
    )

    assert_nil public_event_ticket_price(event)
  end

  test "public_event_visibility_badges labels scheduled ready_for_publish events as geplant" do
    event = events(:needs_review_one)
    event.status = "ready_for_publish"
    event.published_at = 2.hours.from_now

    assert_equal [ { label: "Geplant", css_class: "status-badge-ready" } ], public_event_visibility_badges(event)
    assert_not public_frontend_visible?(event)
  end
end
