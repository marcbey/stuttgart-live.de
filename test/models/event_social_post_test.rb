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

  test "keeps retry eligibility after a failed publish" do
    social_post = events(:published_one).event_social_posts.create!(
      platform: "facebook",
      status: "approved",
      caption: "Caption",
      target_url: "https://example.com/events/published-event",
      image_url: "https://example.com/published.jpg",
      approved_at: Time.current,
      approved_by: users(:one)
    )

    social_post.mark_failed!("Meta down")

    assert social_post.failed?
    assert social_post.ready_for_publish?
  end
end
