require "test_helper"

class Backend::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:needs_review_one)
    @next_event = events(:needs_review_two)
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
    assert_includes response.body, "value=\"published\""
    assert_includes response.body, "Veranstalter"
    assert_includes response.body, "Promoter-ID"
    assert_select "input[name='starts_after'][value='#{Date.current.iso8601}']"
  end

  test "apply filters stores values in session and redirects to clean url" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      query: "Review Artist",
      organizer: "Music Circus",
      starts_after: "2026-07-01",
      starts_before: "2026-07-31"
    }

    assert_redirected_to backend_events_url(status: "needs_review")
    follow_redirect!
    assert_select "input[name='query'][value='Review Artist']"
    assert_select "input[name='organizer'][value='Music Circus']"
    assert_select "input[name='starts_after'][value='2026-07-01']"
    assert_select "input[name='starts_before'][value='2026-07-31']"
  end

  test "next event preference endpoint stores value in session" do
    sign_in_as(@user)

    post next_event_preference_backend_events_url, params: { enabled: "0" }

    assert_response :success

    get backend_events_url
    assert_response :success
    assert_includes response.body, "data-next-event-enabled-value=\"false\""
  end

  test "status filter is persisted in session" do
    sign_in_as(@user)

    get backend_events_url(status: "needs_review")
    assert_response :success
    assert_includes response.body, "value=\"needs_review\""

    get backend_events_url
    assert_response :success
    assert_includes response.body, "value=\"needs_review\""
  end

  test "clear filters removes session filter values" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      query: "Review Artist",
      organizer: "Music Circus",
      starts_after: "2026-07-01",
      starts_before: "2026-07-31"
    }

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      clear_filters: "1"
    }

    assert_redirected_to backend_events_url(status: "needs_review")
    follow_redirect!
    assert_select "input[name='query']"
    assert_select "input[name='organizer']"
    assert_select "input[name='starts_after']"
    assert_select "input[name='starts_before']"
    assert_select "input#query[value='Review Artist']", count: 0
    assert_select "input#organizer[value='Music Circus']", count: 0
    assert_select "input#starts_after[value='2026-07-01']", count: 0
    assert_select "input[name='starts_after'][value='#{Date.current.iso8601}']"
    assert_select "input#starts_before[value='2026-07-31']", count: 0
  end

  test "organizer filter matches organizer_name" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      organizer: "music circus"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_includes response.body, "editor_form_event_#{@next_event.id}"
    assert_not_includes response.body, "editor_form_event_#{@event.id}"
  end

  test "organizer filter matches promoter_id" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      organizer: "10135"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_includes response.body, "editor_form_event_#{@event.id}"
    assert_not_includes response.body, "editor_form_event_#{@next_event.id}"
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

  test "update stores next event preference from editor form param" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        title: "Neu betitelt",
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        status: "needs_review"
      },
      next_event_enabled: "0"
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)

    get backend_events_url
    assert_response :success
    assert_includes response.body, "data-next-event-enabled-value=\"false\""
  end

  test "turbo update renders next filtered event when next event preference is enabled" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      query: "Review Event"
    }

    patch backend_event_url(@event), params: {
      event: {
        title: "Review Event Updated",
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        status: "needs_review"
      },
      inbox_status: "needs_review",
      next_event_enabled: "1"
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, "target=\"events_list\""
    assert_includes response.body, "editor_form_event_#{@next_event.id}"
  end

  test "turbo update wraps to first filtered event when current event is last" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      query: "Review Event"
    }

    patch backend_event_url(@next_event), params: {
      event: {
        title: "Review Event Two Updated",
        artist_name: @next_event.artist_name,
        start_at: @next_event.start_at,
        venue: @next_event.venue,
        city: @next_event.city,
        status: "needs_review"
      },
      inbox_status: "needs_review",
      next_event_enabled: "1"
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, "editor_form_event_#{@event.id}"
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
    assert_includes response.body, event_path(@published_event.slug)
  end

  test "bulk publish updates selected events" do
    sign_in_as(@user)

    patch bulk_backend_events_url, params: {
      bulk_action: "publish",
      event_ids: [ @event.id ]
    }

    assert_redirected_to backend_events_url(status: "published")
    assert_equal "published", @event.reload.status
    assert @event.published_at.present?
  end
end
