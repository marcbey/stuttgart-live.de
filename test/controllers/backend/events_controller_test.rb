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

  test "blogger cannot access the event backend" do
    sign_in_as(users(:blogger))

    get backend_events_url

    assert_redirected_to root_url
  end

  test "index is available for signed in users" do
    sign_in_as(@user)

    get backend_events_url

    assert_response :success
    assert_select ".app-nav-links-group-separated .app-nav-link", text: "Events"
    assert_select ".app-nav-backend-menu", count: 0
    assert_select ".app-nav-links .app-nav-link-active", text: "Events"
    assert_match(/Events.*News.*Importer.*Passwort.*Logout/m, response.body)
    assert_includes response.body, "Event-Inbox"
    assert_includes response.body, "auto-next"
    assert_includes response.body, "name=\"status\""
    assert_includes response.body, "value=\"published\""
    assert_includes response.body, "Promoter-ID"
    assert_includes response.body, "Beginn"
    assert_select "button[aria-label='Suche löschen']"
    assert_select "button[aria-label='Promoter-ID löschen']"
    assert_includes response.body, "Bilder aus Import"
    assert_not_includes response.body, "Ticket-Angebote"
    assert_includes response.body, "startDate.setHours(startDate.getHours()-1)"
    assert_includes response.body, "data-next-event-enabled-value=\"false\""
    assert_select "input[name='starts_after'][value='#{Date.current.iso8601}']"
    assert_select ".backend-topbar-context", text: "Published Artist · Published Event · 01.06.2026 22:00"
    assert_select "#event_topbar_editor_actions a.button", text: "Open"
  end

  test "index shows selected event context in topbar" do
    sign_in_as(@user)

    get backend_events_url(status: "needs_review", event_id: @event.id)

    assert_response :success
    assert_select ".backend-topbar-context", text: "Review Artist · Review Event · 10.07.2026 22:00"
  end

  test "show keeps active inbox status in editor form" do
    sign_in_as(@user)

    get backend_event_url(@event, status: "needs_review")

    assert_response :success
    assert_select "turbo-frame#event_editor", count: 1
    assert_select "div#event_editor", count: 0
    assert_select "div#event_editor_panel", count: 1
    assert_select "input[name='inbox_status'][value='needs_review']"
    assert_select "input[name='event[promoter_id]'][value='#{@event.promoter_id}']"
    assert_select "input[readonly]#event_#{@event.id}_promoter_id_display", count: 0
    assert_select "input[name='event[highlighted]'][type='checkbox']"
    assert_select "input[name='event[support]']", count: 1
    assert_select "[data-controller='event-image-editor-upload']", minimum: 2
    assert_select "button", text: "Upload", count: 0
    assert_select "input[name='event_image[files][]'][required]", count: 0
    assert_select "input[type='checkbox'][name='event[genre_ids][]'][value='#{genres(:schlager).id}']"
  end

  test "show populates ticket url with the frontend ticket url" do
    sign_in_as(@user)

    get backend_event_url(@published_event, status: "published")

    assert_response :success
    assert_select "input[name='event[ticket_url]'][value='https://example.com/tickets/published']"
  end

  test "new shows the same editable fields as the event editor" do
    sign_in_as(@user)

    get new_backend_event_url

    assert_response :success
    assert_select "input[name='event[doors_at]']"
    assert_select "input[name='event[homepage_url]']"
    assert_select "input[name='event[instagram_url]']"
    assert_select "input[name='event[facebook_url]']"
    assert_select "input[name='event[promoter_id]']"
    assert_select "input[name='event[ticket_url]']"
    assert_select "input[name='event[highlighted]'][type='checkbox']"
    assert_select "input[name='event[support]']"
    assert_select "textarea[name='event[organizer_notes]']"
    assert_select "input[name='event[show_organizer_notes]'][type='checkbox']"
    assert_select "input[type='hidden'][name='event[genre_ids][]'][value='']"
    assert_select "input[name='event_image[detail_hero_files][]'][type='file']"
    assert_select "input[name='event_image[sub_text]']"
    assert_select "select[name='event_image[grid_variant]']"
    assert_select "input[name='event_image[card_focus_x]'][value='50.0']"
    assert_select "input[name='event_image[card_focus_y]'][value='50.0']"
    assert_select "input[name='event_image[card_zoom]'][value='100.0']"
    assert_select "input[name='event_image[slider_files][]'][type='file']"
    assert_select "input[name='event_image[slider_alt_text]']"
    assert_select "[data-controller='event-image-preupload']"
    assert_select "[data-event-image-crop-preview-target='previewBox']", count: 1
    assert_includes response.body, "startDate.setHours(startDate.getHours()-1)"
  end

  test "slider image meta actions keep delete separate from meta form" do
    sign_in_as(@user)
    image = create_event_image(event: @event, purpose: EventImage::PURPOSE_SLIDER)

    get backend_events_url(status: "needs_review", event_id: @event.id)

    assert_response :success
    assert_select ".slider-image-editor-card .slider-image-meta-form", count: 1
    assert_select ".slider-image-editor-card .slider-image-meta-actions .button_to", count: 1
    assert_select "input[value='Save Meta']", count: 0
    assert_select "button", text: "Save Meta", count: 0
    assert_select ".slider-image-editor-card .slider-image-meta-form form", count: 0
  end

  test "show includes event image crop fields in the main editor form" do
    sign_in_as(@user)
    image = create_event_image(event: @event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

    get backend_events_url(status: "needs_review", event_id: @event.id)

    assert_response :success
    assert_select "label[for='event_image_sub_text']", text: "Copyright"
    assert_select "label[for='event_image_grid_variant']", text: "Grid-Variante"
    assert_select "input[name='event_image[sub_text]'][form='editor_form_event_#{@event.id}'][value='#{image.sub_text}']"
    assert_select "input[name='event_image[grid_variant]'][form='editor_form_event_#{@event.id}'][value='#{image.grid_variant}']"
    assert_select "select[name='event_image[grid_variant]'] option[value='']", count: 0
    assert_select "input[name='event_image[card_focus_x]'][form='editor_form_event_#{@event.id}'][value='#{image.card_focus_x_value}']"
    assert_select "input[name='event_image[card_focus_y]'][form='editor_form_event_#{@event.id}'][value='#{image.card_focus_y_value}']"
    assert_select "input[name='event_image[card_zoom]'][form='editor_form_event_#{@event.id}'][value='#{image.card_zoom_value}']"
    assert_select "[data-event-image-crop-preview-target='previewBox']", count: 1
    assert_includes response.body, "<code>1x1</code> ist der Standard"
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

  test "index shows empty state in event list when filters match no events" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      query: "Keine Treffer"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_select "#events_list .event-list-count", text: /0/
    assert_select "#events_list .empty-state", text: "Keine Events zur aktuellen Filterung."
    assert_select "#events_list .event-list-item", count: 0
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
    assert_select ".status-badge-import-new", text: "New"
    assert_select ".status-badge-import-updated", count: 0
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
    offer = @event.event_offers.create!(
      source: "manual",
      source_event_id: @event.id.to_s,
      ticket_url: "https://tickets.example/original",
      priority_rank: 0,
      sold_out: false
    )

    patch backend_event_url(@event), params: {
      event: {
        title: "Neu betitelt",
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        doors_at: doors_at,
        venue: @event.venue,
        city: @event.city,
        support: "Special Guest",
        organizer_notes: "Eigene Hinweise\nZweite Zeile",
        show_organizer_notes: "1",
        homepage_url: "https://example.com",
        instagram_url: "https://instagram.com/example",
        facebook_url: "https://facebook.com/example",
        highlighted: "1",
        ticket_url: "https://tickets.example/updated",
        status: "needs_review"
      }
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    @event.reload
    assert_equal "Neu betitelt", @event.title
    assert_equal doors_at.to_i, @event.doors_at.to_i
    assert_equal "Special Guest", @event.support
    assert_equal "Eigene Hinweise\nZweite Zeile", @event.organizer_notes
    assert_predicate @event, :show_organizer_notes?
    assert_equal "https://example.com", @event.homepage_url
    assert_equal "https://instagram.com/example", @event.instagram_url
    assert_equal "https://facebook.com/example", @event.facebook_url
    assert_predicate @event, :highlighted?
    assert_equal "https://tickets.example/updated", offer.reload.resolved_ticket_url
    assert_equal "https://tickets.example/updated", @event.preferred_ticket_offer&.resolved_ticket_url
  end

  test "creates manual event with preuploaded images and extended editor fields" do
    sign_in_as(@user)
    start_at = Time.zone.parse("2026-08-18 20:00:00")
    doors_at = Time.zone.parse("2026-08-18 19:00:00")
    hero_blob = direct_uploaded_blob(filename: "hero.png")
    slider_blob_one = direct_uploaded_blob(filename: "slider-1.png")
    slider_blob_two = direct_uploaded_blob(filename: "slider-2.png")

    assert_difference("Event.count", 1) do
      assert_difference("EventImage.count", 3) do
        assert_difference("EventOffer.count", 1) do
        post backend_events_url, params: {
          event: {
            artist_name: "Manual Artist",
            title: "Manual Tour",
            start_at: start_at,
            doors_at: doors_at,
            venue: "Im Wizemann",
            city: "Stuttgart",
            support: "Local Opener",
            organizer_notes: "Bitte früh erscheinen",
            show_organizer_notes: "1",
            badge_text: "Highlight",
            homepage_url: "https://example.com",
            instagram_url: "https://instagram.com/manual",
            facebook_url: "https://facebook.com/manual",
            youtube_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            promoter_id: "10135",
            highlighted: "1",
            ticket_url: "https://tickets.example/manual-tour",
            event_info: "Lange Beschreibung",
            editor_notes: "Interne Notiz",
            status: "needs_review",
            genre_ids: [ genres(:pop).id.to_s ]
          },
          event_image: {
            detail_hero_signed_ids: [ hero_blob.signed_id ],
            sub_text: "Foto: Haus",
            grid_variant: EventImage::GRID_VARIANT_2X1,
            card_focus_x: "18",
            card_focus_y: "72",
            card_zoom: "145",
            slider_signed_ids: [ slider_blob_one.signed_id, slider_blob_two.signed_id ],
            slider_alt_text: "Slider Alt",
            slider_sub_text: "Slider Sub"
          }
        }
        end
      end
    end

    created = Event.order(:id).last
    assert_redirected_to backend_events_url(status: "ready_for_publish", event_id: created.id)
    assert_equal doors_at.to_i, created.doors_at.to_i
    assert_equal "Local Opener", created.support
    assert_equal "Bitte früh erscheinen", created.organizer_notes
    assert_predicate created, :show_organizer_notes?
    assert_equal "https://example.com", created.homepage_url
    assert_equal "https://instagram.com/manual", created.instagram_url
    assert_equal "https://facebook.com/manual", created.facebook_url
    assert_equal "10135", created.promoter_id
    assert_predicate created, :highlighted?
    assert_equal "ready_for_publish", created.status
    assert_equal [ "Pop" ], created.genres.order(:name).pluck(:name)
    assert_equal "https://tickets.example/manual-tour", created.preferred_ticket_offer&.resolved_ticket_url
    assert_equal "manual", created.preferred_ticket_offer&.source
    assert_equal 1, created.event_images.detail_hero.count
    assert_equal 2, created.event_images.slider.count
    assert_equal "Foto: Haus", created.event_images.detail_hero.first.sub_text
    assert_equal EventImage::GRID_VARIANT_2X1, created.event_images.detail_hero.first.grid_variant
    assert_equal 18.0, created.event_images.detail_hero.first.card_focus_x_value
    assert_equal 72.0, created.event_images.detail_hero.first.card_focus_y_value
    assert_equal 145.0, created.event_images.detail_hero.first.card_zoom_value
    assert_equal [ "Slider Alt" ], created.event_images.slider.distinct.pluck(:alt_text)
    assert_equal [ "Slider Sub" ], created.event_images.slider.distinct.pluck(:sub_text)
    assert_nothing_raised { created.event_images.detail_hero.first.processed_optimized_variant }
    created.event_images.slider.each do |image|
      assert_nothing_raised { image.processed_optimized_variant }
    end
  end

  test "rerenders new form when a preuploaded image signed id is invalid" do
    sign_in_as(@user)

    assert_no_difference("Event.count") do
      post backend_events_url, params: {
        event: {
          artist_name: "Manual Artist",
          title: "Manual Tour",
          start_at: Time.zone.parse("2026-08-18 20:00:00"),
          venue: "Im Wizemann",
          city: "Stuttgart",
          status: "needs_review"
        },
        event_image: {
          detail_hero_signed_ids: [ "invalid-signed-id" ]
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "temporäre Upload ist ungültig oder abgelaufen"
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
    @event.update!(
      source_snapshot: {
        "sources" => [
          {
            "source" => "eventim",
            "external_event_id" => "evt-123",
            "raw_payload" => { "name" => "Payload Event" }
          }
        ]
      }
    )

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
    assert_includes response.body, "<turbo-stream action=\"replace\" target=\"event_editor\">"
    assert_includes response.body, "<turbo-frame id=\"event_editor\">"
    assert_includes response.body, "id=\"event_editor_panel\""
    assert_includes response.body, "event-image-editor-upload"
    assert_includes response.body, "event_image_section"
    assert_includes response.body, "slider_images_section"
    assert_includes response.body, "Bilder aus Import"
    assert_includes response.body, "payload-entry"
    assert_not_includes response.body, "payload-block"
    assert_not_includes response.body, "Ticket-Angebote"
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

  test "top save persists event image crop settings" do
    sign_in_as(@user)
    image = create_event_image(event: @event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

    patch backend_event_url(@event), params: {
      event: {
        title: @event.title,
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        status: "needs_review"
      },
      event_image: {
        sub_text: "Foto: Neues Copyright",
        grid_variant: EventImage::GRID_VARIANT_1X2,
        card_focus_x: "18",
        card_focus_y: "72",
        card_zoom: "145"
      },
      next_event_enabled: "0"
    }, as: :turbo_stream

    assert_response :success
    assert_equal "Foto: Neues Copyright", image.reload.sub_text
    assert_equal EventImage::GRID_VARIANT_1X2, image.reload.grid_variant
    assert_equal 18.0, image.card_focus_x_value
    assert_equal 72.0, image.card_focus_y_value
    assert_equal 145.0, image.card_zoom_value
  end

  test "update keeps explicitly opened event when auto-next is disabled" do
    sign_in_as(@user)

    post apply_filters_backend_events_url, params: {
      status: "published",
      query: "definitely-no-match"
    }

    patch backend_event_url(@published_event), params: {
      event: {
        title: "Published Event Updated",
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published"
      },
      inbox_status: "published",
      next_event_enabled: "0"
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @published_event.id)
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
    assert_select "button", text: "Publish", count: 0
    assert_select "#event_editor_panel .editor-header-badges a", text: "Frontend", count: 0
    assert_select "#event-editor-tab-event[aria-selected='true']", count: 1
    assert_select "#event-editor-tab-event-image[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-slider-images[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-llm-enrichment", count: 0
    assert_no_match(/LLM enriched/i, response.body)
  end

  test "editor shows llm enrichment tabs and read-only raw response when enrichment exists" do
    sign_in_as(@user)

    create_llm_enrichment(event: @published_event)

    get backend_event_url(@published_event)

    assert_response :success
    assert_select "#event-editor-tab-event[aria-selected='true']", count: 1
    assert_select "#event-editor-tab-event-image[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-slider-images[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-llm-enrichment[aria-selected='false']", count: 1
    assert_select "#event-editor-panel-event-image[hidden]", count: 1
    assert_select "#event-editor-panel-slider-images[hidden]", count: 1
    assert_select "#event-editor-panel-llm-enrichment[hidden]", count: 1
    assert_select "textarea[name='event[llm_enrichment_attributes][genre_list]']", count: 1
    assert_select "textarea[name='event[llm_enrichment_attributes][raw_response_json]']", count: 0
    assert_includes response.body, "&quot;artist_description&quot;: &quot;LLM Artist Beschreibung&quot;"
    assert_includes response.body, "&quot;genre&quot;: ["
  end

  test "editor shows event image and slider tabs without llm enrichment" do
    sign_in_as(@user)

    get backend_event_url(@published_event, editor_tab: "event_image")

    assert_response :success
    assert_select "#event-editor-tab-event[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-event-image[aria-selected='true']", count: 1
    assert_select "#event-editor-tab-slider-images[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-llm-enrichment", count: 0
    assert_select "#event-editor-panel-event[hidden]", count: 1
    assert_select "#event-editor-panel-event-image:not([hidden])", count: 1
    assert_select "#event-editor-panel-slider-images[hidden]", count: 1
    assert_select "input[name='editor_tab'][value='event_image']", count: 1
  end

  test "update stores nested llm enrichment fields from editor" do
    sign_in_as(@user)
    create_llm_enrichment(event: @published_event)

    patch backend_event_url(@published_event), params: {
      editor_tab: "llm_enrichment",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        llm_enrichment_attributes: {
          id: @published_event.llm_enrichment.id,
          venue: "Neues LLM Venue",
          genre_list: "Indie\nRock",
          artist_description: "Aktualisierte Artist-Beschreibung",
          event_description: "Aktualisierte Event-Beschreibung",
          venue_description: "Aktualisierte Venue-Beschreibung",
          youtube_link: "https://youtube.example/updated",
          instagram_link: "https://instagram.example/updated",
          homepage_link: "https://homepage.example/updated",
          facebook_link: "https://facebook.example/updated"
        }
      }
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @published_event.id)

    enrichment = @published_event.reload.llm_enrichment
    assert_equal "Neues LLM Venue", enrichment.venue
    assert_equal [ "Indie", "Rock" ], enrichment.genre
    assert_equal "Aktualisierte Artist-Beschreibung", enrichment.artist_description
    assert_equal "Aktualisierte Event-Beschreibung", enrichment.event_description
    assert_equal "Aktualisierte Venue-Beschreibung", enrichment.venue_description
    assert_equal "https://youtube.example/updated", enrichment.youtube_link
    assert_equal "https://instagram.example/updated", enrichment.instagram_link
    assert_equal "https://homepage.example/updated", enrichment.homepage_link
    assert_equal "https://facebook.example/updated", enrichment.facebook_link
  end

  test "turbo update keeps llm tab active after successful save" do
    sign_in_as(@user)
    create_llm_enrichment(event: @published_event)

    patch backend_event_url(@published_event), params: {
      inbox_status: "published",
      next_event_enabled: "0",
      editor_tab: "llm_enrichment",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        llm_enrichment_attributes: {
          id: @published_event.llm_enrichment.id,
          event_description: "Neu aus Turbo gespeichert"
        }
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="event_editor"'
    assert_includes response.body, 'id="event-editor-tab-llm-enrichment"'
    assert_includes response.body, 'aria-selected="true"'
    assert_includes response.body, 'name="editor_tab"'
    assert_includes response.body, 'value="llm_enrichment"'
    assert_equal "Neu aus Turbo gespeichert", @published_event.reload.llm_enrichment.event_description
  end

  test "turbo update keeps event image tab active after successful save" do
    sign_in_as(@user)

    patch backend_event_url(@published_event), params: {
      inbox_status: "published",
      next_event_enabled: "0",
      editor_tab: "event_image",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="event_editor"'
    assert_includes response.body, 'id="event-editor-tab-event-image"'
    assert_includes response.body, 'name="editor_tab"'
    assert_includes response.body, 'value="event_image"'
    assert_match(/id="event-editor-tab-event-image"[^>]*aria-selected="true"/, response.body)
  end

  test "validation error keeps llm tab active and does not persist changes" do
    sign_in_as(@user)
    create_llm_enrichment(event: @published_event, event_description: "Vorheriger Text")

    patch backend_event_url(@published_event), params: {
      inbox_status: "published",
      next_event_enabled: "0",
      editor_tab: "llm_enrichment",
      event: {
        title: @published_event.title,
        artist_name: "",
        start_at: @published_event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        llm_enrichment_attributes: {
          id: @published_event.llm_enrichment.id,
          event_description: "Nicht gespeichert"
        }
      }
    }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, 'target="event_editor"'
    assert_includes response.body, 'id="event-editor-tab-llm-enrichment"'
    assert_includes response.body, 'aria-selected="true"'
    assert_includes response.body, "Event konnte nicht gespeichert werden."
    assert_equal "Published Artist", @published_event.reload.artist_name
    assert_equal "Vorheriger Text", @published_event.llm_enrichment.event_description
  end

  test "validation error keeps slider images tab active" do
    sign_in_as(@user)

    patch backend_event_url(@published_event), params: {
      inbox_status: "published",
      next_event_enabled: "0",
      editor_tab: "slider_images",
      event: {
        title: @published_event.title,
        artist_name: "",
        start_at: @published_event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published"
      }
    }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, 'target="event_editor"'
    assert_includes response.body, 'id="event-editor-tab-slider-images"'
    assert_includes response.body, 'name="editor_tab"'
    assert_includes response.body, 'value="slider_images"'
    assert_match(/id="event-editor-tab-slider-images"[^>]*aria-selected="true"/, response.body)
    assert_includes response.body, "Event konnte nicht gespeichert werden."
    assert_equal "Published Artist", @published_event.reload.artist_name
  end

  test "ready_for_publish event editor does not show unpublish button" do
    sign_in_as(@user)

    patch unpublish_backend_event_url(@published_event)
    get backend_event_url(@published_event)

    assert_response :success
    assert_select "button", text: "Unpublish", count: 0
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
    assert_includes response.body, "<turbo-stream action=\"replace\" target=\"event_editor\">"
    assert_includes response.body, "<turbo-frame id=\"event_editor\">"
    assert_includes response.body, "id=\"event_editor_panel\""
    assert_includes response.body, "Event wurde depublisht."
    assert_equal "ready_for_publish", @published_event.reload.status
  end

  test "turbo publish keeps active needs_review filter and refreshes inbox" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      inbox_status: "needs_review",
      next_event_enabled: "0",
      save_and_publish: "1",
      event: {
        artist_name: @event.artist_name,
        title: @event.title,
        start_at: @event.start_at.strftime("%Y-%m-%dT%H:%M"),
        doors_at: "",
        venue: @event.venue,
        city: @event.city,
        status: @event.status,
        genre_ids: [ genres(:rock).id.to_s ]
      }
    }, as: :turbo_stream

    assert_response :success
    assert_equal "published", @event.reload.status
    assert_includes response.body, 'target="event_topbar_context"'
    assert_includes response.body, 'target="event_topbar_editor_actions"'
    assert_includes response.body, 'target="events_list"'
    assert_includes response.body, @next_event.artist_name
    assert_includes response.body, 'target="event_editor"'
    assert_includes response.body, "editor_form_event_#{@next_event.id}"
    assert_includes response.body, "Publish"
  end

  test "turbo unpublish keeps active published filter and refreshes inbox" do
    sign_in_as(@user)
    other_published_event = Event.create!(
      artist_name: "Another Published Artist",
      title: "Another Published Event",
      start_at: Time.zone.parse("2026-06-02 20:00:00"),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 2.days.ago,
      published_by: @user,
      completeness_score: 100
    )

    patch unpublish_backend_event_url(@published_event), params: { inbox_status: "published" }, as: :turbo_stream

    assert_response :success
    assert_equal "ready_for_publish", @published_event.reload.status
    assert_includes response.body, 'target="event_topbar_context"'
    assert_includes response.body, 'target="event_topbar_editor_actions"'
    assert_includes response.body, 'target="events_list"'
    assert_includes response.body, other_published_event.artist_name
    assert_includes response.body, 'target="event_editor"'
    assert_includes response.body, "editor_form_event_#{other_published_event.id}"
    assert_includes response.body, "/backend/events/#{other_published_event.id}/unpublish"
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

  def uploaded_image
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_image.png"),
      "image/png"
    )
  end

  def direct_uploaded_blob(filename:)
    File.open(Rails.root.join("test/fixtures/files/test_image.png")) do |file|
      ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: filename,
        content_type: "image/png"
      )
    end
  end

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

  def create_llm_enrichment(event:, event_description: "LLM Event Beschreibung")
    event.create_llm_enrichment!(
      source_run: import_runs(:one),
      artist_description: "LLM Artist Beschreibung",
      event_description: event_description,
      venue_description: "LLM Venue Beschreibung",
      genre: [ "Indie" ],
      model: "gpt-test",
      prompt_version: "v1",
      raw_response: {
        "artist_description" => "LLM Artist Beschreibung",
        "genre" => [ "Indie" ]
      }
    )
  end
end
