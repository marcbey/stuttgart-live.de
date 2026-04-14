require "test_helper"

class Meta::PublishEventSocialPostJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @event = events(:published_one)
  end

  test "publishes the social post through the publisher service" do
    social_post = @event.event_social_posts.create!(
      platform: "facebook",
      status: "publishing",
      caption: "Caption",
      target_url: "https://example.com/events/#{@event.slug}",
      image_url: "https://example.com/published.jpg",
      approved_at: Time.current,
      approved_by: @user
    )

    original_publisher = Meta::EventSocialPostPublisher
    Meta.send(:remove_const, :EventSocialPostPublisher)
    Meta.const_set(:EventSocialPostPublisher, StubPublisher)

    Meta::PublishEventSocialPostJob.perform_now(social_post.id, @user.id)

    social_post.reload
    assert_equal "published", social_post.status
    assert_equal "page-post-1", social_post.remote_post_id
    assert_equal @user, social_post.published_by
  ensure
    Meta.send(:remove_const, :EventSocialPostPublisher)
    Meta.const_set(:EventSocialPostPublisher, original_publisher)
  end

  private

  class StubPublisher
    def call(event_social_post:, user:)
      event_social_post.mark_published!(
        user:,
        remote_media_id: "photo-1",
        remote_post_id: "page-post-1",
        payload: { "publish_response" => { "ok" => true } }
      )
    end
  end
end
