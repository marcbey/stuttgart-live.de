require "test_helper"

class Backend::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:needs_review_one)
    @user = users(:one)
  end

  test "requires authentication" do
    get backend_events_url

    assert_redirected_to new_session_url
  end

  test "index is available for signed in users" do
    sign_in_as(@user)

    get backend_events_url

    assert_response :success
    assert_includes response.body, "Event-Inbox"
    assert_includes response.body, "Filter entfernen"
    assert_includes response.body, "name=\"status\""
    assert_includes response.body, "value=\"needs_review\""
  end

  test "updates event" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        title: "Neu betitelt",
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        status: "needs_review"
      }
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    assert_equal "Neu betitelt", @event.reload.title
  end

  test "bulk publish updates selected events" do
    sign_in_as(@user)

    patch bulk_backend_events_url, params: {
      bulk_action: "publish",
      event_ids: [ @event.id ]
    }

    assert_redirected_to backend_events_url
    assert_equal "published", @event.reload.status
    assert @event.published_at.present?
  end
end
