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

    social_post = Meta::EventSocialPostDraftSync.new.call(event:, platform: "instagram")

    assert social_post.publish_image_instagram.attached?
    assert_equal "instagram", social_post.platform
    assert_equal social_post.publish_image_instagram_url, social_post.image_url
    assert_match(%r{\Ahttps://example.com/}, social_post.preview_image_url)
    assert_match(%r{\Ahttps://example.com/}, social_post.publish_image_instagram_url)
    assert_equal "image/jpeg", social_post.publish_image_instagram.blob.content_type
    assert_equal "published-event-instagram-social-card.jpg", social_post.publish_image_instagram.blob.filename.to_s
    assert_equal [ 1080, 1350 ], image_dimensions(social_post.publish_image_instagram.download)
    assert_equal 1080, social_post.payload_snapshot.dig("rendered_variants", "instagram", "width")
    assert_equal 1350, social_post.payload_snapshot.dig("rendered_variants", "instagram", "height")
    assert_equal "Published Artist", social_post.payload_snapshot.dig("card_text", "artist_name")
    assert_equal "01.06.2026 · LKA Longhorn", social_post.payload_snapshot.dig("card_text", "meta_line")
    assert_nil social_post.payload_snapshot.dig("rendered_variants", "instagram", "title_lines")
  end

  test "creates an independent facebook draft" do
    event = events(:published_one)
    event_image = EventImage.new(
      event:,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "Facebook Social Card Hero"
    )
    event_image.file.attach(
      io: StringIO.new(solid_png_binary(width: 2200, height: 1400, rgb: [ 26, 36, 54 ])),
      filename: "facebook-social-card-hero.png",
      content_type: "image/png"
    )
    event_image.save!

    social_post = Meta::EventSocialPostDraftSync.new.call(event:, platform: "facebook")

    assert_equal "facebook", social_post.platform
    assert_equal "draft", social_post.status
    assert social_post.publish_image_instagram.attached?
    assert_equal social_post.publish_image_instagram_url, social_post.image_url
    assert_equal "facebook", social_post.payload_snapshot.fetch("platform")
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
    assert_equal "11.11.2026 CUSTOM VENUE", social_post.payload_snapshot.dig("rendered_variants", "instagram", "meta_line")
  end

  test "refreshes editable drafts after event image changes" do
    event = events(:published_one)
    event.event_social_posts.destroy_all

    event.event_social_posts.create!(
      platform: "instagram",
      status: "approved",
      caption: "Old Instagram caption",
      target_url: "https://example.com/events/old",
      image_url: "https://example.com/old-instagram.jpg",
      payload_snapshot: { "background_source" => "import_image" }
    )
    event.event_social_posts.create!(
      platform: "facebook",
      status: "failed",
      caption: "Old Facebook caption",
      target_url: "https://example.com/events/old",
      image_url: "https://example.com/old-facebook.jpg",
      payload_snapshot: { "background_source" => "import_image" }
    )
    event_image = EventImage.new(
      event:,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "New Eventbild"
    )
    event_image.file.attach(
      io: StringIO.new(solid_png_binary(width: 2200, height: 1400, rgb: [ 80, 120, 180 ])),
      filename: "new-eventbild.png",
      content_type: "image/png"
    )
    event_image.save!

    refreshed_posts = Meta::EventSocialPostDraftSync.new.refresh_after_event_image_change!(event:)
    posts = event.event_social_posts.reload.index_by(&:platform)

    assert_equal 2, refreshed_posts.size
    assert_equal "draft", posts.fetch("instagram").status
    assert_equal "draft", posts.fetch("facebook").status
    assert_equal "editorial_event_image", posts.fetch("instagram").payload_snapshot.fetch("background_source")
    assert_equal "editorial_event_image", posts.fetch("facebook").payload_snapshot.fetch("background_source")
    assert posts.fetch("instagram").publish_image_instagram.attached?
    assert posts.fetch("facebook").publish_image_instagram.attached?
  end

  test "does not refresh published posts after event image changes" do
    event = events(:published_one)
    event.event_social_posts.destroy_all
    published_post = event.event_social_posts.create!(
      platform: "facebook",
      status: "published",
      caption: "Published caption",
      target_url: "https://example.com/events/published",
      image_url: "https://example.com/published.jpg",
      payload_snapshot: { "background_source" => "import_image" },
      published_at: Time.current,
      remote_post_id: "page_post"
    )
    event_image = EventImage.new(
      event:,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "New Eventbild"
    )
    event_image.file.attach(
      io: StringIO.new(solid_png_binary(width: 2200, height: 1400, rgb: [ 80, 120, 180 ])),
      filename: "new-eventbild-published.png",
      content_type: "image/png"
    )
    event_image.save!

    Meta::EventSocialPostDraftSync.new.refresh_after_event_image_change!(event:)

    assert_equal "published", published_post.reload.status
    assert_equal "import_image", published_post.payload_snapshot.fetch("background_source")
    assert_equal "https://example.com/published.jpg", published_post.image_url
  end
end
