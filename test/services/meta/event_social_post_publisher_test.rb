require "test_helper"

class Meta::EventSocialPostPublisherTest < ActiveSupport::TestCase
  test "marks the social post as published on success" do
    social_post = create_approved_social_post(platform: "facebook")
    platform_publishers = {
      "facebook" => SuccessfulPlatformPublisher.new("media-1", "post-1")
    }
    access_status = SuccessfulAccessStatus.new

    Meta::EventSocialPostPublisher.new(platform_publishers:, access_status:).call(
      event_social_post: social_post,
      user: users(:one)
    )

    social_post.reload
    assert_equal "published", social_post.status
    assert_equal "media-1", social_post.remote_media_id
    assert_equal "post-1", social_post.remote_post_id
    assert_equal users(:one), social_post.published_by
    assert_equal 1, social_post.publish_attempts.count
    assert_equal "succeeded", social_post.publish_attempts.last.status
  end

  test "marks the social post as failed when publishing raises" do
    social_post = create_approved_social_post(platform: "facebook")
    platform_publishers = {
      "facebook" => FailingPlatformPublisher.new
    }
    access_status = SuccessfulAccessStatus.new

    error = assert_raises(Meta::Error) do
      Meta::EventSocialPostPublisher.new(platform_publishers:, access_status:).call(
        event_social_post: social_post,
        user: users(:one)
      )
    end

    assert_equal "Meta unavailable", error.message

    social_post.reload
    assert_equal "failed", social_post.status
    assert_equal "Meta unavailable", social_post.error_message
    assert social_post.ready_for_publish?
    assert_equal "failed", social_post.publish_attempts.last.status
  end

  test "fails early when meta access status is invalid" do
    social_post = create_approved_social_post(platform: "facebook")
    platform_publishers = {
      "facebook" => SuccessfulPlatformPublisher.new("media-1", "post-1")
    }

    error = assert_raises(Meta::Error) do
      Meta::EventSocialPostPublisher.new(
        platform_publishers:,
        access_status: FailingAccessStatus.new
      ).call(event_social_post: social_post, user: users(:one))
    end

    assert_equal "Meta-Token ist abgelaufen oder ungültig.", error.message

    social_post.reload
    assert_equal "failed", social_post.status
    assert_equal "Meta-Token ist abgelaufen oder ungültig.", social_post.error_message
    assert_equal "failed", social_post.publish_attempts.last.status
  end

  private

  def create_approved_social_post(platform:)
    events(:published_one).event_social_posts.create!(
      platform:,
      status: "draft",
      caption: "Caption",
      target_url: "https://example.com/events/published-event",
      image_url: "https://example.com/published.jpg"
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

  class SuccessfulAccessStatus
    def ensure_publishable!(force: false)
      true
    end
  end

  class FailingAccessStatus
    def ensure_publishable!(force: false)
      raise Meta::Error, "Meta-Token ist abgelaufen oder ungültig."
    end
  end
end
