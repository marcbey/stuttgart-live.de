require "test_helper"

class EventOfferTest < ActiveSupport::TestCase
  OWN_SHOP = "https://partnershop.easyticket.de/3b38659fef6bcc38e100c728435ba8e9".freeze
  GENERAL_SHOP = "https://partnershop.easyticket.de/c2b3ee865fb7464a68403f97966923d8".freeze

  setup do
    AppSetting.find_or_initialize_by(key: AppSetting::SKS_PROMOTER_IDS_KEY).update!(value: %w[10135 10136 382])
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "existing third party offers use the general shop and preserve the ticket event id" do
    offer = easyticket_offer(promoter_id: "7008")
    offer.ticket_url = "#{OWN_SHOP}/event/105758?quantity=2#tickets"

    assert_equal "#{GENERAL_SHOP}/event/105758?quantity=2#tickets", offer.resolved_ticket_url
    assert_equal "#{OWN_SHOP}/event/105758?quantity=2#tickets", offer.ticket_url
  end

  test "Russ and Music Circus keep the own shop even when the stored link uses the general shop" do
    %w[382 10135 10136 141].each do |promoter_id|
      offer = easyticket_offer(promoter_id: promoter_id)
      offer.ticket_url = "#{GENERAL_SHOP}/event/105758"

      assert_equal "#{OWN_SHOP}/event/105758", offer.resolved_ticket_url, promoter_id
    end
  end

  test "organizer names identify manual Russ and Music Circus events" do
    [ "RUSS Live", "SKS Michael Russ GmbH", "Südwestdeutsche Konzertdirektion Michael Russ GmbH",
      "Music Circus Concertbüro GmbH &CoKG", "Music Circus Concertbüro GmbH & Co. KG", "10135" ].each do |name|
      offer = easyticket_offer(promoter_name: name)
      offer.source = "manual"

      assert_equal "#{OWN_SHOP}/event/105758", offer.resolved_ticket_url, name
    end
  end

  test "Music Circus is recognized from Eventim or a merged Easy Ticket source" do
    offer = easyticket_offer(promoter_id: "36", primary_source: "eventim")
    assert_equal "#{OWN_SHOP}/event/105758", offer.resolved_ticket_url

    offer.event.assign_attributes(promoter_id: "4595", source_snapshot: {
      "sources" => [ { "source" => "easyticket", "promoter_id" => "141" } ]
    })
    assert_equal "#{OWN_SHOP}/event/105758", offer.resolved_ticket_url
  end

  test "unrelated promoters and highlighted events still use the general shop" do
    offer = easyticket_offer(promoter_id: "36", primary_source: "easyticket", highlighted: true)
    assert_equal "#{GENERAL_SHOP}/event/105758", offer.resolved_ticket_url

    offer.event.assign_attributes(promoter_id: nil, promoter_name: "Anderer Veranstalter")
    offer.source = "manual"
    assert_equal "#{GENERAL_SHOP}/event/105758", offer.resolved_ticket_url
  end

  test "direct Easy Ticket event links use the correct partner shop" do
    offer = easyticket_offer(promoter_id: "141")
    [ "https://www.easyticket.de/concert/stuttgart/105758/", "https://easyticket.de/event/105758" ].each do |url|
      offer.ticket_url = url
      assert_equal "#{OWN_SHOP}/event/105758", offer.resolved_ticket_url
    end
  end

  test "shop home links use the correct shop without inventing an event id" do
    offer = easyticket_offer
    offer.source = "manual"
    offer.ticket_url = OWN_SHOP
    assert_equal GENERAL_SHOP, offer.resolved_ticket_url
  end

  test "Easy Ticket links without a ticket event id use the shop homepage" do
    offer = easyticket_offer
    offer.ticket_url = "https://www.easyticket.de/dauerkarten/dauerkarte-hauptfeld-porsche-tennis-grand-prix-2026"
    assert_equal GENERAL_SHOP, offer.resolved_ticket_url
  end

  test "routing follows changed organizer assignments without another import" do
    offer = easyticket_offer
    assert_equal "#{GENERAL_SHOP}/event/105758", offer.resolved_ticket_url

    offer.event.promoter_id = "141"
    assert_equal "#{OWN_SHOP}/event/105758", offer.resolved_ticket_url
  end

  test "other providers lookalike domains and non event resources are not rewritten" do
    offer = easyticket_offer(promoter_id: "141")
    [ "https://eventim.de/event/105758", "https://reservix.de/tickets/105758",
      "https://easyticket.de.example.org/event/105758", "https://example.org/easyticket.de/event/105758",
      "https://www.easyticket.de/files/information.pdf", "not a valid URL", "" ].each do |url|
      offer.ticket_url = url
      assert_equal url, offer.resolved_ticket_url
    end
  end

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

  private

  def easyticket_offer(**attributes)
    EventOffer.new(
      event: Event.new(**attributes), source: "easyticket", source_event_id: "62290",
      ticket_url: "#{GENERAL_SHOP}/event/105758"
    )
  end
end
