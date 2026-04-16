require "test_helper"

class Meta::EventSocialPostDraftSyncTest < ActiveSupport::TestCase
  test "creates the instagram publish asset for a social draft" do
    event = events(:published_one)
    event_image = EventImage.new(
      event:,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "Social Card Hero"
    )
    event_image.file.attach(
      io: StringIO.new(solid_png_binary(width: 2200, height: 1400, rgb: [ 26, 36, 54 ])),
      filename: "social-card-hero.png",
      content_type: "image/png"
    )
    event_image.save!

    social_post = Meta::EventSocialPostDraftSync.new.call(event:, platform: "facebook")

    assert social_post.publish_image_instagram.attached?
    assert_equal "instagram", social_post.platform
    assert_equal social_post.publish_image_instagram_url, social_post.image_url
    assert_match(%r{\Ahttps://example.com/}, social_post.preview_image_url)
    assert_match(%r{\Ahttps://example.com/}, social_post.publish_image_instagram_url)
    assert_equal [ 1080, 1350 ], image_dimensions(social_post.publish_image_instagram.download)
    assert_equal 1080, social_post.payload_snapshot.dig("rendered_variants", "instagram", "width")
    assert_equal 1350, social_post.payload_snapshot.dig("rendered_variants", "instagram", "height")
    assert_equal "Published Artist", social_post.payload_snapshot.dig("card_text", "artist_name")
    assert_equal "01.06.2026 · LKA Longhorn", social_post.payload_snapshot.dig("card_text", "meta_line")
    assert_nil social_post.payload_snapshot.dig("rendered_variants", "instagram", "title_lines")
  end

  test "refreshes rendered assets after manual card text changes" do
    event = events(:published_one)
    event_image = EventImage.new(
      event:,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "Social Card Hero"
    )
    event_image.file.attach(
      io: StringIO.new(solid_png_binary(width: 2200, height: 1400, rgb: [ 26, 36, 54 ])),
      filename: "social-card-hero-refresh.png",
      content_type: "image/png"
    )
    event_image.save!

    social_post = Meta::EventSocialPostDraftSync.new.call(event:, platform: "facebook")
    social_post.assign_attributes(card_artist_name: "Custom Artist", card_meta_line: "11.11.2026 · Custom Venue")
    social_post.save!

    Meta::EventSocialPostDraftSync.new.refresh_rendered_assets!(social_post)

    social_post.reload
    assert_equal "Custom Artist", social_post.payload_snapshot.dig("card_text", "artist_name")
    assert_equal "11.11.2026 · Custom Venue", social_post.payload_snapshot.dig("card_text", "meta_line")
    assert_equal "11.11.2026 · CUSTOM VENUE", social_post.payload_snapshot.dig("rendered_variants", "instagram", "meta_line")
  end
end
