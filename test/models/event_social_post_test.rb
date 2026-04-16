require "test_helper"

class EventSocialPostTest < ActiveSupport::TestCase
  test "validates unique platform per event" do
    events(:published_one).event_social_posts.create!(
      platform: "facebook",
      status: "draft",
      caption: "Caption"
    )

    duplicate = events(:published_one).event_social_posts.build(
      platform: "facebook",
      status: "draft",
      caption: "Another caption"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:platform], "ist bereits vergeben"
  end

  test "requires valid draft urls for approval" do
    social_post = events(:published_one).event_social_posts.build(
      platform: "facebook",
      status: "draft",
      caption: "Caption",
      target_url: "not-a-url",
      image_url: nil
    )

    assert_equal [ "Event-Link fehlt oder ist ungültig.", "Bild-Link fehlt oder ist ungültig." ], social_post.approval_errors
    assert_raises(Meta::Error) { social_post.ensure_approvable! }
  end

  test "rejects localhost publish urls because meta cannot fetch them" do
    social_post = events(:published_one).event_social_posts.build(
      platform: "facebook",
      status: "draft",
      caption: "Caption",
      target_url: "http://localhost:3000/events/test",
      image_url: "http://localhost:3000/rails/active_storage/blobs/test.png"
    )

    assert_equal [
      "Event-Link ist nicht öffentlich erreichbar.",
      "Bild-Link ist nicht öffentlich erreichbar."
    ], social_post.approval_errors
  end

  test "keeps retry eligibility after a failed publish" do
    social_post = events(:published_one).event_social_posts.create!(
      platform: "facebook",
      status: "draft",
      caption: "Caption",
      target_url: "https://example.com/events/published-event",
      image_url: "https://example.com/published.jpg"
    )

    social_post.mark_failed!("Meta down")

    assert social_post.failed?
    assert social_post.ready_for_publish?
  end

  test "keeps republish eligibility after a successful publish" do
    social_post = events(:published_one).event_social_posts.create!(
      platform: "instagram",
      status: "published",
      caption: "Caption",
      target_url: "https://example.com/events/published-event",
      image_url: "https://example.com/published.jpg",
      published_at: Time.current
    )

    assert social_post.published?
    assert social_post.ready_for_publish?
    assert_empty social_post.publish_errors
  end

  test "builds a facebook post url from the remote post id" do
    social_post = events(:published_one).event_social_posts.build(
      platform: "facebook",
      status: "published",
      caption: "Caption",
      remote_post_id: "1065331226666212_122101097324744282"
    )

    assert_equal "https://www.facebook.com/1065331226666212/posts/122101097324744282", social_post.facebook_post_url
    assert_equal social_post.facebook_post_url, social_post.published_post_url
  end

  test "reads instagram permalink from the payload snapshot" do
    social_post = events(:published_one).event_social_posts.build(
      platform: "instagram",
      status: "published",
      caption: "Caption",
      payload_snapshot: {
        "media" => {
          "id" => "1789",
          "permalink" => "https://www.instagram.com/p/ABC123/"
        }
      }
    )

    assert_equal "https://www.instagram.com/p/ABC123/", social_post.instagram_post_url
    assert_equal social_post.instagram_post_url, social_post.published_post_url
  end
end
