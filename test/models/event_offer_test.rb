require "test_helper"

class EventOfferTest < ActiveSupport::TestCase
  test "resolved_ticket_url replaces {event_id} placeholder" do
    offer = event_offers(:published_one_offer)
    offer.ticket_url = "https://tickets.example/event/{event_id}"

    assert_equal "https://tickets.example/event/ext-published-1", offer.resolved_ticket_url
  end

  test "resolved_ticket_url replaces %{event_id} placeholder" do
    offer = event_offers(:published_one_offer)
    offer.ticket_url = "https://tickets.example/event/%{event_id}"

    assert_equal "https://tickets.example/event/ext-published-1", offer.resolved_ticket_url
  end

  test "resolved_ticket_url removes duplicate trailing event_id" do
    offer = event_offers(:published_one_offer)
    offer.ticket_url = "https://tickets.example/event/ext-published-1/ext-published-1"

    assert_equal "https://tickets.example/event/ext-published-1", offer.resolved_ticket_url
  end
end
