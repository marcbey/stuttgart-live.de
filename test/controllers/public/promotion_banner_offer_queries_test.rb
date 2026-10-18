require "test_helper"

class Public::PromotionBannerOfferQueriesTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    @events = 3.times.map do |index|
      event = Event.create!(
        source_fingerprint: "test::banner-offers::#{index}",
        artist_name: "Banner Query Artist #{index}",
        title: "Banner Query Programme #{index}",
        start_at: (index + 1).days.from_now.change(hour: 20),
        venue_record: venues(:lka_longhorn),
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        promotion_banner: index.even?,
        highlighted: index.positive?
      )
      event.promotion_banner_image.attach(create_uploaded_blob(filename: "banner-offers-#{index}.png"))
      event.event_offers.create!(
        source: "manual", source_event_id: "banner-offer-#{index}",
        ticket_url: "https://tickets.example.test/#{index}", priority_rank: 0,
        sold_out: index == 2
      )
      event
    end
  end

  teardown { travel_back }

  test "promotion and highlight slider events batch ticket offers" do
    queries = []
    callback = lambda do |event|
      next if event.payload[:name] == "SCHEMA" || event.payload[:cached]

      queries << event.payload[:sql].to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get events_path }

    assert_response :success
    @events.each do |event|
      assert_select ".design-preview-banner-card .design-preview-card-title", text: event.artist_name, minimum: 1
    end
    assert_select ".design-preview-banner-card .promotion-banner-cta", text: "Ausverkauft", minimum: 1
    assert_empty queries.grep(/FROM "event_offers".*"event_id" =/m)
  end
end
