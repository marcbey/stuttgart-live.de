require "test_helper"

class Meta::EventSocialPostDraftBuilderTest < ActiveSupport::TestCase
  test "builds draft data from event data and imported background image" do
    draft = Meta::EventSocialPostDraftBuilder.new(
      event: events(:published_one),
      platform: "facebook"
    ).build

    assert_equal "https://example.com/events/published-event", draft.attributes[:target_url]
    assert_nil draft.attributes[:image_url]
    assert_includes draft.attributes[:caption], "Published Artist | Published Event"
    assert_includes draft.attributes[:caption], "Mehr Infos und Tickets:"
    assert_equal "facebook", draft.attributes[:payload_snapshot]["platform"]
    assert_equal "Published Artist", draft.attributes[:payload_snapshot].dig("card_text", "artist_name")
    assert_equal "01.06.2026 · LKA Longhorn", draft.attributes[:payload_snapshot].dig("card_text", "meta_line")
    assert_equal :remote_url, draft.background_source.source_type
    assert_equal "https://example.com/published.jpg", draft.background_source.remote_url
    assert_equal "import_image", draft.attributes[:payload_snapshot]["background_source"]
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

    draft = Meta::EventSocialPostDraftBuilder.new(
      event:,
      platform: "facebook"
    ).build

    assert_equal :attachment, draft.background_source.source_type
    assert_equal event_image.file.blob, draft.background_source.attachment.blob
    assert_equal "editorial_event_image", draft.background_source.source_label
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

    draft = Meta::EventSocialPostDraftBuilder.new(event:, platform: "instagram").build

    assert_equal "https://example.com/events/promotion-only-event", draft.attributes[:target_url]
    assert_equal :attachment, draft.background_source.source_type
    assert_equal event.promotion_banner_image.blob, draft.background_source.attachment.blob
    assert_equal "promotion_banner_image", draft.background_source.source_label
  end
end
