require "test_helper"

class EventSocialPublicationStatusTest < ActiveSupport::TestCase
  test "ignores legacy facebook records and uses the instagram status" do
    event = events(:published_one)
    event.event_social_posts.destroy_all

    event.event_social_posts.create!(
      platform: "facebook",
      status: "published",
      caption: "Caption",
      target_url: "https://example.com/events/#{event.slug}",
      image_url: "https://example.com/facebook.jpg",
      approved_at: Time.current,
      approved_by: users(:one),
      published_at: Time.current,
      published_by: users(:one)
    )
    event.event_social_posts.create!(
      platform: "instagram",
      status: "failed",
      caption: "Caption",
      target_url: "https://example.com/events/#{event.slug}",
      image_url: "https://example.com/instagram.jpg",
      approved_at: Time.current,
      approved_by: users(:one),
      error_message: "Meta-Fehler"
    )

    assert_equal "failed", event.reload.social_publication_status
  end

  test "returns published when the instagram post is published" do
    event = events(:published_one)
    event.event_social_posts.destroy_all

    event.event_social_posts.create!(
      platform: "instagram",
      status: "published",
      caption: "Caption",
      target_url: "https://example.com/events/#{event.slug}",
      image_url: "https://example.com/instagram.jpg",
      approved_at: Time.current,
      approved_by: users(:one),
      published_at: Time.current,
      published_by: users(:one)
    )

    assert_equal "published", event.reload.social_publication_status
  end
end
