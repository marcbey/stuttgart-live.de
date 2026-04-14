require "test_helper"

class Backend::EventSocialPostsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @event = events(:published_one)
    @user = users(:one)
    sign_in_as(@user)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    sign_out
  end

  test "create generates a draft for a platform" do
    assert_difference -> { @event.event_social_posts.count }, 1 do
      post backend_event_event_social_posts_url(@event), params: {
        platform: "facebook",
        inbox_status: "published"
      }
    end

    social_post = @event.event_social_posts.order(:id).last
    assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
    assert_equal "facebook", social_post.platform
    assert_equal "draft", social_post.status
  end

  test "update resets an approved draft back to draft when caption changes" do
    social_post = create_approved_social_post(@event, platform: "facebook")

    patch backend_event_event_social_post_url(@event, social_post), params: {
      inbox_status: "published",
      event_social_post: { caption: "Neue Caption" }
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
    social_post.reload
    assert_equal "draft", social_post.status
    assert_nil social_post.approved_at
    assert_equal "Neue Caption", social_post.caption
  end

  test "approve rejects invalid drafts" do
    social_post = @event.event_social_posts.create!(
      platform: "facebook",
      status: "draft",
      caption: "Caption",
      target_url: nil,
      image_url: nil
    )

    patch approve_backend_event_event_social_post_url(@event, social_post), params: {
      inbox_status: "published"
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
    follow_redirect!
    assert_match "Event-Link fehlt oder ist ungültig.", response.body
    assert_match "Bild-Link fehlt oder ist ungültig.", response.body
  end

  test "publish enqueues an approved social post" do
    social_post = create_approved_social_post(@event, platform: "facebook")

    assert_enqueued_with(job: Meta::PublishEventSocialPostJob, args: [ social_post.id, @user.id ]) do
      post publish_backend_event_event_social_post_url(@event, social_post), params: {
        inbox_status: "published"
      }
    end

    assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
    social_post.reload
    assert_equal "publishing", social_post.status
    follow_redirect!
    assert_match "Facebook-Post wird im Hintergrund veröffentlicht.", response.body
  end

  test "quick publish creates and enqueues a platform post" do
    assert_difference -> { @event.event_social_posts.count }, 1 do
      assert_enqueued_jobs 1, only: Meta::PublishEventSocialPostJob do
        post quick_publish_backend_event_event_social_posts_url(@event), params: {
          platform: "instagram",
          inbox_status: "published"
        }
      end
    end

    assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
    social_post = @event.event_social_posts.find_by!(platform: "instagram")
    assert_enqueued_with(job: Meta::PublishEventSocialPostJob, args: [ social_post.id, @user.id ])
    assert_equal "publishing", social_post.status
    assert_nil social_post.remote_post_id
    assert_equal @user, social_post.approved_by
    assert_nil social_post.published_by
    follow_redirect!
    assert_match "Instagram-Post wird im Hintergrund veröffentlicht.", response.body
  end

  test "quick publish skips already published platform posts" do
    social_post = @event.event_social_posts.create!(
      platform: "facebook",
      status: "published",
      caption: "Caption",
      target_url: "https://example.com/events/#{@event.slug}",
      image_url: "https://example.com/published.jpg",
      approved_at: Time.current,
      approved_by: @user,
      published_at: Time.current,
      published_by: @user,
      remote_media_id: "photo-1",
      remote_post_id: "page-post-1"
    )

    assert_no_difference -> { @event.event_social_posts.count } do
      post quick_publish_backend_event_event_social_posts_url(@event), params: {
        platform: "facebook",
        inbox_status: "published"
      }
    end

    assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
    follow_redirect!
    assert_match "Facebook-Post ist bereits veröffentlicht.", response.body
    assert_equal social_post, @event.event_social_posts.find_by!(platform: "facebook")
  end

  test "publish rejects events that are not yet live before enqueuing" do
    event = Event.create!(
      slug: "scheduled-social-event",
      source_fingerprint: "test::social::scheduled",
      title: "Scheduled Social Event",
      artist_name: "Scheduled Artist",
      normalized_artist_name: "scheduledartist",
      start_at: Time.zone.local(2026, 9, 10, 20, 0, 0),
      status: "ready_for_publish",
      published_at: 2.days.from_now,
      venue_record: venues(:lka_longhorn)
    )
    event.import_event_images.create!(
      source: "manual",
      image_type: "large",
      role: "cover",
      aspect_hint: "landscape",
      position: 0,
      image_url: "https://example.com/scheduled.jpg"
    )
    social_post = Meta::EventSocialPostDraftSync.new.call(event:, platform: "instagram")
    social_post.approve!(user: @user)

    assert_no_enqueued_jobs only: Meta::PublishEventSocialPostJob do
      post publish_backend_event_event_social_post_url(event, social_post), params: {
        inbox_status: "ready_for_publish"
      }
    end

    assert_redirected_to backend_events_url(status: "ready_for_publish", event_id: event.id, editor_tab: "social")
    social_post.reload
    assert_equal "approved", social_post.status
    follow_redirect!
    assert_match "Event ist noch nicht öffentlich live.", response.body
  end

  private

  def create_approved_social_post(event, platform:)
    event.event_social_posts.create!(
      platform:,
      status: "approved",
      caption: "Caption",
      target_url: "https://example.com/events/#{event.slug}",
      image_url: "https://example.com/published.jpg",
      approved_at: Time.current,
      approved_by: @user
    )
  end
end
