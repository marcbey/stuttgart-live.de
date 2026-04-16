require "test_helper"

class Meta::PublishEventSocialPostJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @event = events(:published_one)
  end

  test "publishes the social post through the publisher service" do
    social_post = @event.event_social_posts.create!(
      platform: "instagram",
      status: "publishing",
      caption: "Caption",
      target_url: "https://example.com/events/#{@event.slug}",
      image_url: "https://example.com/published.jpg"
    )

    original_publisher = Meta::EventSocialPostPublisher
    Meta.send(:remove_const, :EventSocialPostPublisher)
    Meta.const_set(:EventSocialPostPublisher, StubPublisher)

    Meta::PublishEventSocialPostJob.perform_now(social_post.id, @user.id)

    social_post.reload
    assert_equal "published", social_post.status
    assert_nil social_post.remote_post_id
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
        remote_post_id: nil,
        payload: { "publish_response" => { "ok" => true } }
      )
    end
  end
end
