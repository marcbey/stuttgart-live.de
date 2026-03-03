require "test_helper"

class Backend::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:needs_review_one)
    @published_event = events(:published_one)
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
    assert_includes response.body, "nächsten Event anzeigen"
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

  test "updates event via turbo stream and renders flash message" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        title: "Neu per Turbo",
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        status: "needs_review"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "Event wurde gespeichert."
    assert_equal "Neu per Turbo", @event.reload.title
  end

  test "save and publish updates event and publishes it" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        title: "Neu und publiziert",
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        status: "needs_review"
      },
      save_and_publish: "1"
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @event.id)
    assert_equal "published", @event.reload.status
    assert @event.published_at.present?
    assert_includes flash[:notice], "gespeichert und publiziert"
  end

  test "update does not clear existing genres when genre_ids are absent" do
    sign_in_as(@user)

    patch backend_event_url(@published_event), params: {
      event: {
        title: "Published Event Updated",
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published"
      }
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @published_event.id)
    assert_equal [ "Rock" ], @published_event.reload.genres.order(:name).pluck(:name)
  end

  test "published event editor does not show save and publish button" do
    sign_in_as(@user)

    get backend_event_url(@published_event)

    assert_response :success
    assert_not_includes response.body, "Speichern & Publizieren"
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
