require "test_helper"

class Meta::EventSocialPostPublisherTest < ActiveSupport::TestCase
  test "marks the social post as published on success" do
    social_post = create_approved_social_post(platform: "instagram")
    platform_publishers = {
      "instagram" => SuccessfulPlatformPublisher.new("media-1", nil)
    }
    access_status = SuccessfulAccessStatus.new

    Meta::EventSocialPostPublisher.new(platform_publishers:, access_status:).call(
      event_social_post: social_post,
      user: users(:one)
    )

    social_post.reload
    assert_equal "published", social_post.status
    assert_equal "media-1", social_post.remote_media_id
    assert_nil social_post.remote_post_id
    assert_equal users(:one), social_post.published_by
    assert_equal 1, social_post.publish_attempts.count
    assert_equal "succeeded", social_post.publish_attempts.last.status
  end

  test "marks the social post as failed when publishing raises" do
    social_post = create_approved_social_post(platform: "instagram")
    platform_publishers = {
      "instagram" => FailingPlatformPublisher.new
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

  test "publishes only the requested instagram post when a facebook page is selected" do
    social_post = create_approved_social_post(platform: "instagram")
    facebook_post = create_approved_social_post(platform: "facebook")
    platform_publishers = {
      "instagram" => SuccessfulInstagramPublisher.new("ig-media-1"),
      "facebook" => SuccessfulFacebookPublisher.new("fb-media-1", "page-1_post-1")
    }
    access_status = SuccessfulAccessStatus.new
    draft_sync = DraftSyncStub.new(facebook_post)
    connection_resolver = ResolverStub.with_facebook_page

    Meta::EventSocialPostPublisher.new(
      platform_publishers:,
      access_status:,
      draft_sync:,
      connection_resolver:
    ).call(event_social_post: social_post, user: users(:one))

    social_post.reload
    facebook_post.reload

    assert_equal "published", social_post.status
    assert_equal "ig-media-1", social_post.remote_media_id
    assert_equal "draft", facebook_post.status
    assert_nil facebook_post.remote_media_id
    assert_nil facebook_post.remote_post_id
    assert_equal %w[succeeded], social_post.publish_attempts.pluck(:status)
    assert_empty facebook_post.publish_attempts
  end

  test "publishes a facebook post independently" do
    facebook_post = create_approved_social_post(platform: "facebook")
    platform_publishers = {
      "facebook" => SuccessfulFacebookPublisher.new("fb-media-1", "page-1_post-1")
    }

    Meta::EventSocialPostPublisher.new(
      platform_publishers:,
      access_status: SuccessfulAccessStatus.new,
      connection_resolver: ResolverStub.with_facebook_page
    ).call(event_social_post: facebook_post, user: users(:one))

    facebook_post.reload

    assert_equal "published", facebook_post.status
    assert_equal "fb-media-1", facebook_post.remote_media_id
    assert_equal "page-1_post-1", facebook_post.remote_post_id
    assert_equal %w[succeeded], facebook_post.publish_attempts.pluck(:status)
  end

  test "does not attempt facebook when instagram publishing fails" do
    social_post = create_approved_social_post(platform: "instagram")
    facebook_post = create_approved_social_post(platform: "facebook")
    facebook_publisher = TrackingFacebookPublisher.new
    platform_publishers = {
      "instagram" => FailingPlatformPublisher.new,
      "facebook" => facebook_publisher
    }

    assert_raises(Meta::Error) do
      Meta::EventSocialPostPublisher.new(
        platform_publishers:,
        access_status: SuccessfulAccessStatus.new,
        draft_sync: DraftSyncStub.new(facebook_post),
        connection_resolver: ResolverStub.with_facebook_page
      ).call(event_social_post: social_post, user: users(:one))
    end

    refute_predicate facebook_publisher, :called?
    facebook_post.reload
    assert_equal "draft", facebook_post.status
  end

  test "fails early when meta access status is invalid" do
    social_post = create_approved_social_post(platform: "instagram")
    platform_publishers = {
      "instagram" => SuccessfulPlatformPublisher.new("media-1", nil)
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
      Meta::InstagramPublisher::Result.new(
        remote_media_id: @remote_media_id,
        remote_post_id: @remote_post_id,
        payload: { "platform" => event_social_post.platform }
      )
    end
  end

  class SuccessfulInstagramPublisher
    def initialize(remote_media_id)
      @remote_media_id = remote_media_id
    end

    def publish!(event_social_post:)
      Meta::InstagramPublisher::Result.new(
        remote_media_id: @remote_media_id,
        remote_post_id: nil,
        payload: { "platform" => event_social_post.platform }
      )
    end
  end

  class SuccessfulFacebookPublisher
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

  class TrackingFacebookPublisher
    def initialize
      @called = false
    end

    def publish!(**)
      @called = true
      raise "should not be called"
    end

    def called?
      @called
    end
  end

  class SuccessfulAccessStatus
    def ensure_publishable!(force: false, platform: nil)
      true
    end
  end

  class FailingAccessStatus
    def ensure_publishable!(force: false, platform: nil)
      raise Meta::Error, "Meta-Token ist abgelaufen oder ungültig."
    end
  end

  class DraftSyncStub
    def initialize(facebook_post)
      @facebook_post = facebook_post
    end

    def sync_facebook_mirror!(_instagram_post)
      @facebook_post
    end
  end

  class ResolverStub
    def self.with_facebook_page
      connection = SocialConnection.create!(
        provider: "meta",
        platform: "facebook",
        auth_mode: "facebook_login_for_business",
        connection_status: "connected",
        user_access_token: "user-token",
        user_token_expires_at: 40.days.from_now,
        granted_scopes: %w[pages_show_list pages_read_engagement pages_manage_posts instagram_basic instagram_content_publish]
      )
      facebook_target = connection.social_connection_targets.create!(
        target_type: "facebook_page",
        external_id: "page-123",
        name: "Test SL",
        access_token: "page-token",
        selected: true,
        status: "selected"
      )
      connection.social_connection_targets.create!(
        target_type: "instagram_account",
        external_id: "ig-123",
        username: "sl_test_26",
        parent_target: facebook_target,
        selected: true,
        status: "selected"
      )

      new(connection)
    end

    def initialize(connection)
      @connection = connection
    end

    def connection
      @connection
    end

    def connection_for(platform)
      @connection if platform.to_s == @connection.platform
    end
  end
end
