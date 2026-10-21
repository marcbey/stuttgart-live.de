require "test_helper"

class Public::PromotionBannerVariantQueriesTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    3.times do |index|
      event = Event.create!(
        source_fingerprint: "test::banner-variants::#{index}",
        artist_name: "Variant Query Artist #{index}",
        title: "Variant Query Programme #{index}",
        start_at: (index + 1).days.from_now.change(hour: 20),
        venue_record: venues(:lka_longhorn),
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        promotion_banner: index.even?,
        highlighted: index.positive?
      )
      event.promotion_banner_image.attach(create_uploaded_blob(filename: "banner-variants-#{index}.png"))
      EventImages::PreparePublicImagesJob.perform_now(event)
    end
  end

  teardown { travel_back }

  test "homepage preloads tracked banner variants for promotions and highlights" do
    queries = []
    callback = lambda do |event|
      next if event.payload[:name] == "SCHEMA" || event.payload[:cached]

      queries << event.payload[:sql].to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get events_path }

    assert_response :success
    assert_select ".design-preview-banner-card img[srcset]", minimum: 3
    assert_empty queries.grep(/FROM "active_storage_variant_records".*"blob_id" =.*"variation_digest" =/m)
  end
end
