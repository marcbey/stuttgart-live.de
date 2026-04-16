require "test_helper"

class Backend::EventSocialPostsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  META_ACCESS_STATUS_CLASS = Meta::AccessStatus
  META_ACCESS_STATUS_RESULT = Meta::AccessStatus::Status

  setup do
    @event = events(:published_one)
    @user = users(:one)
    attach_social_background!(@event)
    sign_in_as(@user)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    sign_out
  end

  test "create generates a draft for a platform" do
    with_stubbed_meta_access_status do
      assert_difference -> { @event.event_social_posts.count }, 1 do
        post backend_event_event_social_posts_url(@event), params: {
          inbox_status: "published"
        }
      end

      social_post = @event.event_social_posts.order(:id).last
      assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
      assert_equal "instagram", social_post.platform
      assert_equal "draft", social_post.status
    end
  end

  test "update resets an approved draft back to draft when caption changes" do
    social_post = create_approved_social_post(@event, platform: "instagram")

    with_stubbed_meta_access_status do
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
  end

  test "update stores custom card text and refreshes rendered metadata" do
    social_post = Meta::EventSocialPostDraftSync.new.call(event: @event, platform: "instagram")

    with_stubbed_meta_access_status do
      patch backend_event_event_social_post_url(@event, social_post), params: {
        inbox_status: "published",
        event_social_post: {
          caption: social_post.caption,
          card_artist_name: "Custom Artist",
          card_meta_line: "11.11.2026 · Custom Venue"
        }
      }

      assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
      social_post.reload
      assert_equal "Custom Artist", social_post.payload_snapshot.dig("card_text", "artist_name")
      assert_equal "11.11.2026 · Custom Venue", social_post.payload_snapshot.dig("card_text", "meta_line")
      assert_equal "11.11.2026 · CUSTOM VENUE", social_post.payload_snapshot.dig("rendered_variants", "instagram", "meta_line")
    end
  end

  test "publish rejects invalid drafts" do
    social_post = @event.event_social_posts.create!(
      platform: "instagram",
      status: "draft",
      caption: "Caption",
      target_url: nil,
      image_url: nil
    )

    with_stubbed_meta_access_status do
      post publish_backend_event_event_social_post_url(@event, social_post), params: {
        inbox_status: "published"
      }

      assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
      follow_redirect!
      assert_match "Event-Link fehlt oder ist ungültig.", response.body
      assert_match "Bild-Link fehlt oder ist ungültig.", response.body
    end
  end

  test "publish enqueues a draft social post directly" do
    social_post = create_draft_social_post(@event, platform: "instagram")
    access_status = StubMetaAccessStatus.new

    with_stubbed_meta_access_status(access_status) do
      assert_enqueued_with(job: Meta::PublishEventSocialPostJob, args: [ social_post.id, @user.id ]) do
        post publish_backend_event_event_social_post_url(@event, social_post), params: {
          inbox_status: "published"
        }
      end

      assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
      social_post.reload
      assert_equal "publishing", social_post.status
      assert_nil social_post.approved_at
      follow_redirect!
      assert_match "Instagram-Post wird im Hintergrund veröffentlicht.", response.body
    end
  end

  test "quick publish creates and enqueues a platform post" do
    access_status = StubMetaAccessStatus.new

    with_stubbed_meta_access_status(access_status) do
      assert_difference -> { @event.event_social_posts.count }, 1 do
        assert_enqueued_jobs 1, only: Meta::PublishEventSocialPostJob do
          post quick_publish_backend_event_event_social_posts_url(@event), params: {
            inbox_status: "published"
          }
        end
      end

      assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
      social_post = @event.event_social_posts.find_by!(platform: "instagram")
      assert_enqueued_with(job: Meta::PublishEventSocialPostJob, args: [ social_post.id, @user.id ])
      assert_equal "publishing", social_post.status
      assert_nil social_post.remote_post_id
      assert_nil social_post.approved_by
      assert_nil social_post.published_by
      follow_redirect!
      assert_match "Instagram-Post wird im Hintergrund veröffentlicht.", response.body
    end
  end

  test "publish blocks enqueue when meta token check fails" do
    social_post = create_draft_social_post(@event, platform: "instagram")
    failing_access_status = FailingMetaAccessStatus.new

    with_stubbed_meta_access_status(failing_access_status) do
      assert_no_enqueued_jobs only: Meta::PublishEventSocialPostJob do
        post publish_backend_event_event_social_post_url(@event, social_post), params: {
          inbox_status: "published"
        }
      end

      assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
      social_post.reload
      assert_equal "draft", social_post.status
      follow_redirect!
      assert_match "Meta-Token ist abgelaufen oder ungültig.", response.body
    end
  end

  test "quick publish skips an already published instagram post" do
    social_post = @event.event_social_posts.create!(
      platform: "instagram",
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

    with_stubbed_meta_access_status do
      assert_no_difference -> { @event.event_social_posts.count } do
        post quick_publish_backend_event_event_social_posts_url(@event), params: {
          inbox_status: "published"
        }
      end

      assert_redirected_to backend_events_url(status: "published", event_id: @event.id, editor_tab: "social")
      follow_redirect!
      assert_match "Instagram-Post ist bereits veröffentlicht.", response.body
      assert_equal social_post, @event.event_social_posts.find_by!(platform: "instagram")
    end
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
    attach_social_background!(event)
    social_post = Meta::EventSocialPostDraftSync.new.call(event:, platform: "instagram")

    with_stubbed_meta_access_status do
      assert_no_enqueued_jobs only: Meta::PublishEventSocialPostJob do
        post publish_backend_event_event_social_post_url(event, social_post), params: {
          inbox_status: "ready_for_publish"
        }
      end

      assert_redirected_to backend_events_url(status: "ready_for_publish", event_id: event.id, editor_tab: "social")
      social_post.reload
      assert_equal "draft", social_post.status
      follow_redirect!
      assert_match "Event ist noch nicht öffentlich live.", response.body
    end
  end

  private

  def attach_social_background!(event)
    return if event.event_image.present?

    event_image = event.event_images.build(
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "Social Test Hero"
    )
    event_image.file.attach(
      io: StringIO.new(solid_png_binary(width: 2200, height: 1400, rgb: [ 18, 45, 51 ])),
      filename: "social-test-hero.png",
      content_type: "image/png"
    )
    event_image.save!
  end

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

  def create_draft_social_post(event, platform:)
    event.event_social_posts.create!(
      platform:,
      status: "draft",
      caption: "Caption",
      target_url: "https://example.com/events/#{event.slug}",
      image_url: "https://example.com/published.jpg"
    )
  end

  def with_stubbed_meta_access_status(access_status = StubMetaAccessStatus.new, &block)
    fake_access_status_class = Class.new do
      define_singleton_method(:new) { access_status }
    end

    Meta.send(:remove_const, :AccessStatus)
    Meta.const_set(:AccessStatus, fake_access_status_class)
    yield
  ensure
    Meta.send(:remove_const, :AccessStatus)
    Meta.const_set(:AccessStatus, META_ACCESS_STATUS_CLASS)
  end

  class StubMetaAccessStatus
    def call
      META_ACCESS_STATUS_RESULT.new(
        connection_status: "connected",
        state: :ok,
        summary: "Meta-Verbindung ist gültig.",
        details: [],
        checked_at: Time.current,
        expires_at: nil,
        page_name: "Test SL",
        instagram_username: "sl_test_26",
        permissions: [],
        debug_available: false,
        reauth_required: false,
        payload: {}
      )
    end

    def ensure_publishable!(force: false)
      call
    end
  end

  class FailingMetaAccessStatus < StubMetaAccessStatus
    def ensure_publishable!(force: false)
      raise Meta::Error, "Meta-Token ist abgelaufen oder ungültig."
    end
  end
end
