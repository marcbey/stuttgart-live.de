require "test_helper"

class Meta::EventSocialPostPublisherTest < ActiveSupport::TestCase
  test "marks the social post as published on success" do
    social_post = create_approved_social_post(platform: "facebook")
    platform_publishers = {
      "facebook" => SuccessfulPlatformPublisher.new("media-1", "post-1")
    }

    Meta::EventSocialPostPublisher.new(platform_publishers:).call(
      event_social_post: social_post,
      user: users(:one)
    )

    social_post.reload
    assert_equal "published", social_post.status
    assert_equal "media-1", social_post.remote_media_id
    assert_equal "post-1", social_post.remote_post_id
    assert_equal users(:one), social_post.published_by
  end

  test "marks the social post as failed when publishing raises" do
    social_post = create_approved_social_post(platform: "facebook")
    platform_publishers = {
      "facebook" => FailingPlatformPublisher.new
    }

    error = assert_raises(Meta::Error) do
      Meta::EventSocialPostPublisher.new(platform_publishers:).call(
        event_social_post: social_post,
        user: users(:one)
      )
    end

    assert_equal "Meta unavailable", error.message

    social_post.reload
    assert_equal "failed", social_post.status
    assert_equal "Meta unavailable", social_post.error_message
    assert social_post.ready_for_publish?
  end

  private

  def create_approved_social_post(platform:)
    events(:published_one).event_social_posts.create!(
      platform:,
      status: "approved",
      caption: "Caption",
      target_url: "https://example.com/events/published-event",
      image_url: "https://example.com/published.jpg",
      approved_at: Time.current,
      approved_by: users(:one)
    )
  end

  class SuccessfulPlatformPublisher
    def initialize(remote_media_id, remote_post_id)
      @remote_media_id = remote_media_id
      @remote_post_id = remote_post_id
    end

    def publish!(event_social_post:)
      Meta::FacebookPublisher::Result.new(
        remote_media_id: @remote_media_id,
        remote_post_id: @remote_post_id,
        payload: { "platform" => event_social_post.platform }
      )
    end
  end

  class FailingPlatformPublisher
    def publish!(**)
      raise Meta::Error, "Meta unavailable"
    end
  end
end
