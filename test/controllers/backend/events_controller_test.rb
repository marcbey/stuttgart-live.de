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
    assert_includes response.body, "Auto-Weiter"
    assert_includes response.body, "name=\"status\""
    assert_includes response.body, "value=\"published\""
    assert_includes response.body, "Promoter-ID"
    assert_includes response.body, "Beginn"
    assert_includes response.body, "Einlass löschen"
    assert_includes response.body, "Preis: 45 EUR"
    assert_includes response.body, "editor-datetime-clear"
    assert_includes response.body, "startDate.setHours(startDate.getHours()-1)"
    assert_select "input[name='starts_after'][value='#{Date.current.iso8601}']"
  end

  test "slider image meta actions use separate forms for save and delete" do
    sign_in_as(@user)
    image = create_event_image(event: @event, purpose: EventImage::PURPOSE_SLIDER)

    get backend_events_url(status: "needs_review", event_id: @event.id)

    assert_response :success
    assert_select "form##{ActionView::RecordIdentifier.dom_id(image, :meta)}"
    assert_select "button[form='#{ActionView::RecordIdentifier.dom_id(image, :meta)}']", text: "Meta speichern"
    assert_select "form##{ActionView::RecordIdentifier.dom_id(image, :meta)} form", count: 0
  end

  test "index renders status chips without counts and shows filtered event count" do
    sign_in_as(@user)

    get backend_events_url

    assert_response :success
    assert_select ".status-chip strong", count: 0
    assert_select ".filter-merge-row .filter-merge-field", count: 2
    assert_select ".event-list-count", text: /gefilterte Events/
    assert_select "select[name='merge_change_type'][disabled]"
  end

  test "change type filter is enabled when merge scope is last merge" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      merge_scope: "last_merge",
      merge_change_type: "updated"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_select "select[name='merge_scope'] option[selected][value='last_merge']"
    assert_select "select[name='merge_change_type']:not([disabled])"
  end

  test "index does not show import merge button" do
    sign_in_as(@user)

    get backend_events_url

    assert_response :success
    assert_not_includes response.body, "Import-Merge synchronisieren"
  end

  test "apply filters stores values in session and redirects to clean url" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      query: "Review Artist",
      promoter_id: "36",
      starts_after: "2026-07-01",
      starts_before: "2026-07-31"
    }

    assert_redirected_to backend_events_url(status: "needs_review")
    follow_redirect!
    assert_select "input[name='query'][value='Review Artist']"
    assert_select "input[name='promoter_id'][value='36']"
    assert_select "input[name='starts_after'][value='2026-07-01']"
    assert_select "input[name='starts_before'][value='2026-07-31']"
  end

  test "applies merge filters and shows import change badge for created events in latest merge" do
    sign_in_as(@user)

    merge_run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "merge",
      status: "succeeded",
      started_at: Time.zone.parse("2026-03-06 10:00:00"),
      finished_at: Time.zone.parse("2026-03-06 10:05:00")
    )
    @event.event_change_logs.create!(
      action: "merged_create",
      user: nil,
      changed_fields: {},
      metadata: { "merge_run_id" => merge_run.id }
    )
    @next_event.event_change_logs.create!(
      action: "merged_update",
      user: nil,
      changed_fields: {},
      metadata: { "merge_run_id" => merge_run.id }
    )

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      merge_scope: "last_merge",
      merge_change_type: "created"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_includes response.body, "Neu (Import)"
    assert_not_includes response.body, "Aktualisiert (Import)"
    assert_includes response.body, "Review Artist"
    assert_not_includes response.body, "Review Artist Two"
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
      promoter_id: "36",
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
    assert_select "input[name='promoter_id']"
    assert_select "input[name='starts_after']"
    assert_select "input[name='starts_before']"
    assert_select "input#query[value='Review Artist']", count: 0
    assert_select "input#promoter_id[value='36']", count: 0
    assert_select "input#starts_after[value='2026-07-01']", count: 0
    assert_select "input[name='starts_after'][value='#{Date.current.iso8601}']"
    assert_select "input#starts_before[value='2026-07-31']", count: 0
  end

  test "promoter_id filter matches promoter_id" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      promoter_id: "36"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_includes response.body, "editor_form_event_#{@next_event.id}"
    assert_not_includes response.body, "editor_form_event_#{@event.id}"
  end

  test "promoter_id filter supports exact promoter_id matches" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      promoter_id: "10135"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_includes response.body, "editor_form_event_#{@event.id}"
    assert_not_includes response.body, "editor_form_event_#{@next_event.id}"
  end

  test "updates event" do
    sign_in_as(@user)
    doors_at = Time.zone.parse("2026-07-10 18:30:00")

    patch backend_event_url(@event), params: {
      event: {
        title: "Neu betitelt",
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        doors_at: doors_at,
        venue: @event.venue,
        city: @event.city,
        organizer_notes: "Eigene Hinweise\nZweite Zeile",
        show_organizer_notes: "1",
        homepage_url: "https://example.com",
        instagram_url: "https://instagram.com/example",
        facebook_url: "https://facebook.com/example",
        status: "needs_review"
      }
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    @event.reload
    assert_equal "Neu betitelt", @event.title
    assert_equal doors_at.to_i, @event.doors_at.to_i
    assert_equal "Eigene Hinweise\nZweite Zeile", @event.organizer_notes
    assert_predicate @event, :show_organizer_notes?
    assert_equal "https://example.com", @event.homepage_url
    assert_equal "https://instagram.com/example", @event.instagram_url
    assert_equal "https://facebook.com/example", @event.facebook_url
  end

  test "updates event with blank city" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        title: @event.title,
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: "",
        status: "needs_review"
      }
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    assert_nil @event.reload.city
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

  test "save and publish via turbo stream updates nav flash" do
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
    }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "action=\"update\""
    assert_includes response.body, "Event wurde gespeichert und publiziert."
    assert_equal "published", @event.reload.status
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

  test "editor renders genre checkboxes with selected genres" do
    sign_in_as(@user)

    get backend_event_url(@published_event)

    assert_response :success
    assert_select "input[type='hidden'][name='event[genre_ids][]'][value='']"
    assert_select "input[type='checkbox'][name='event[genre_ids][]'][value='#{genres(:rock).id}'][checked='checked']"
    assert_select "input[type='checkbox'][name='event[genre_ids][]'][value='#{genres(:pop).id}']", count: 1
  end

  test "update stores selected genres from editor checkboxes" do
    sign_in_as(@user)

    patch backend_event_url(@published_event), params: {
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        genre_ids: [ genres(:pop).id.to_s ]
      }
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @published_event.id)
    assert_equal [ "Pop" ], @published_event.reload.genres.order(:name).pluck(:name)
  end

  test "published event editor does not show publish button" do
    sign_in_as(@user)

    get backend_event_url(@published_event)

    assert_response :success
    assert_not_includes response.body, "Publizieren"
    assert_includes response.body, event_path(@published_event.slug)
  end

  test "ready_for_publish event editor does not show unpublish button" do
    sign_in_as(@user)

    patch unpublish_backend_event_url(@published_event)
    get backend_event_url(@published_event)

    assert_response :success
    assert_not_includes response.body, "Depublizieren"
  end

  test "unpublish moves published event to ready_for_publish" do
    sign_in_as(@user)

    patch unpublish_backend_event_url(@published_event)

    assert_redirected_to backend_events_url(status: "ready_for_publish", event_id: @published_event.id)
    @published_event.reload
    assert_equal "ready_for_publish", @published_event.status
    assert_nil @published_event.published_at
    assert_nil @published_event.published_by_id
  end

  test "unpublish via turbo stream updates nav flash" do
    sign_in_as(@user)

    patch unpublish_backend_event_url(@published_event), as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "action=\"update\""
    assert_includes response.body, "Event wurde depublisht."
    assert_equal "ready_for_publish", @published_event.reload.status
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

  private

  def create_event_image(event:, purpose:, grid_variant: nil, alt_text: "Alt", sub_text: "Sub")
    image = event.event_images.new(
      purpose: purpose,
      grid_variant: grid_variant,
      alt_text: alt_text,
      sub_text: sub_text
    )

    File.open(Rails.root.join("test/fixtures/files/test_image.png")) do |file|
      image.file.attach(
        io: file,
        filename: "test_image.png",
        content_type: "image/png"
      )
      image.save!
    end

    image
  end
end
