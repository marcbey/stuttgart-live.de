require "test_helper"

class Meta::EventSocialPostDraftBuilderTest < ActiveSupport::TestCase
  test "builds draft attributes from event data and import image" do
    attributes = Meta::EventSocialPostDraftBuilder.new(
      event: events(:published_one),
      platform: "facebook"
    ).attributes

    assert_equal "https://example.com/events/published-event", attributes[:target_url]
    assert_equal "https://example.com/published.jpg", attributes[:image_url]
    assert_includes attributes[:caption], "Published Artist | Published Event"
    assert_includes attributes[:caption], "Mehr Infos und Tickets:"
    assert_equal "facebook", attributes[:payload_snapshot]["platform"]
  end

  test "prefers editorial event image over imported fallback images" do
    event = events(:published_one)
    event_image = EventImage.new(
      event: event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "Hero Alt",
      sub_text: "Hero Sub"
    )
    event_image.file.attach(
      io: StringIO.new(solid_png_binary(width: 2200, height: 1400)),
      filename: "hero-image.png",
      content_type: "image/png"
    )
    event_image.save!

    attributes = Meta::EventSocialPostDraftBuilder.new(
      event:,
      platform: "facebook"
    ).attributes

    assert_match(%r{\Ahttps://example.com/rails/active_storage/}, attributes[:image_url])
    refute_equal "https://example.com/published.jpg", attributes[:image_url]
  end

  test "falls back to promotion banner image when no event image is present" do
    event = Event.create!(
      slug: "promotion-only-event",
      source_fingerprint: "test::social::promotion-only",
      title: "Promotion Only Event",
      artist_name: "Promotion Artist",
      normalized_artist_name: "promotionevent",
      start_at: Time.zone.local(2026, 8, 12, 20, 0, 0),
      status: "published",
      published_at: 1.day.ago,
      venue_record: venues(:lka_longhorn)
    )
    event.promotion_banner_image.attach(
      io: StringIO.new(solid_png_binary(width: 1200, height: 675)),
      filename: "promotion-only.png",
      content_type: "image/png"
    )

    attributes = Meta::EventSocialPostDraftBuilder.new(event:, platform: "instagram").attributes

    assert_equal "https://example.com/events/promotion-only-event", attributes[:target_url]
    assert_match(%r{\Ahttps://example.com/rails/active_storage/}, attributes[:image_url])
  end
end
