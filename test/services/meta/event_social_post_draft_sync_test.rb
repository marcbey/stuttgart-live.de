require "test_helper"

class Meta::EventSocialPostDraftSyncTest < ActiveSupport::TestCase
  test "creates preview and publish assets for a social draft" do
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

    assert social_post.preview_image.attached?
    assert social_post.publish_image_facebook.attached?
    assert social_post.publish_image_instagram.attached?
    assert_equal social_post.publish_image_facebook_url, social_post.image_url
    assert_match(%r{\Ahttps://example.com/}, social_post.preview_image_url)
    assert_match(%r{\Ahttps://example.com/}, social_post.publish_image_facebook_url)
    assert_match(%r{\Ahttps://example.com/}, social_post.publish_image_instagram_url)
    assert_equal [ 1080, 1080 ], image_dimensions(social_post.preview_image.download)
    assert_equal [ 1080, 1080 ], image_dimensions(social_post.publish_image_facebook.download)
    assert_equal [ 1080, 1350 ], image_dimensions(social_post.publish_image_instagram.download)
    assert_equal 1080, social_post.payload_snapshot.dig("rendered_variants", "instagram", "width")
    assert_equal 1350, social_post.payload_snapshot.dig("rendered_variants", "instagram", "height")
    assert_nil social_post.payload_snapshot.dig("rendered_variants", "facebook", "title_lines")
    assert_nil social_post.payload_snapshot.dig("rendered_variants", "instagram", "title_lines")
  end
end
