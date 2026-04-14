require "test_helper"

class Backend::EventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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
    assert_not_includes response.body, "fonts.googleapis.com"
    assert_not_includes response.body, "fonts.gstatic.com"
    assert_select "script[type='module'][src*='/assets/backend']", count: 1
    assert_select "script[type='module'][src*='/assets/public']", count: 0
    assert_select "script[type='module'][src*='/assets/application']", count: 0
    assert_select "link[rel='preload'][as='font'][href*='archivo-narrow-400']", count: 1
    assert_select "link[rel='preload'][as='font'][href*='bebas-neue-400']", count: 0
    assert_select "style[data-local-font-faces]", count: 1
    assert_includes response.body, ActionController::Base.helpers.asset_path("archivo-narrow-700.woff2")
    assert_includes response.body, ActionController::Base.helpers.asset_path("oswald-500.woff2")
    assert_includes response.body, ActionController::Base.helpers.asset_path("oswald-700.woff2")
    assert_not_includes response.body, ActionController::Base.helpers.asset_path("bebas-neue-400.woff2")
    assert_select ".app-nav-links-group-separated .app-nav-link", text: "Events"
    assert_select ".app-nav-backend-menu", count: 0
    assert_select ".app-nav-links .app-nav-link-active", text: "Events"
    assert_match(/Events.*News.*Präsentatoren.*Venues.*Queue.*Passwort.*Logout/m, response.body)
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
    assert_select "#event_topbar_editor_actions a.button", text: "Open"
  end

  test "index does not render a separate topbar context" do
    sign_in_as(@user)

    get backend_events_url(status: "needs_review", event_id: @event.id)

    assert_response :success
    assert_select "#event_editor_panel .editor-header h2", text: "Review Artist"
    assert_select "#event_topbar_editor_actions", count: 1
  end

  test "show keeps active inbox status in editor form" do
    sign_in_as(@user)

    get backend_event_url(@event, status: "needs_review")

    assert_response :success
    assert_select "turbo-frame#event_editor", count: 1
    assert_select "div#event_editor", count: 0
    assert_select "div#event_editor_panel", count: 1
    assert_select "input[name='inbox_status'][value='needs_review']"
    assert_select "input[name='event[promoter_id]']", count: 0
    assert_select "input[readonly]#promoter_display_event_#{@event.id}[value='#{@event.promoter_id}']"
    assert_select ".event-editor-tabs[data-controller='event-editor-tabs']", count: 1
    assert_select ".event-editor-tabs[data-controller='event-editor-tabs event-editor-settings']", count: 0
    assert_select "#event-editor-tab-settings[aria-selected='false']", count: 1
    assert_select "#event-editor-panel-settings[hidden]", count: 1
    assert_select "#event-editor-panel-settings input[name='event[highlighted]'][type='checkbox'][form='editor_form_event_#{@event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner]'][type='checkbox'][form='editor_form_event_#{@event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event_promotion_banner_image[promotion_banner_image_signed_id]'][form='editor_form_event_#{@event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event_promotion_banner_image[remove_promotion_banner_image]'][form='editor_form_event_#{@event.id}']", count: 1
    assert_select "form#editor_form_event_#{@event.id} input[type='hidden'][name='event[promotion_banner]']", count: 0
    assert_select "form#editor_form_event_#{@event.id} input[type='hidden'][name='event[promotion_banner_kicker_text]']", count: 0
    assert_select "form#editor_form_event_#{@event.id} input[type='hidden'][name='event[promotion_banner_cta_text]']", count: 0
    assert_select "input[name='event[support]']", count: 1
    assert_select "#event-editor-panel-event input[name='event[published_at]'][type='hidden'][value='']", count: 1
    assert_select "#event-editor-panel-event input[name='event[published_at]'][type='datetime-local']", count: 1
    assert_select "[data-controller='event-image-editor-upload']", minimum: 2
    assert_select "button", text: "Upload", count: 0
    assert_select "input[name='event_image[files][]'][required]", count: 0
    assert_select "#event-editor-panel-event .editor-genre-section", count: 0
    assert_select "input[name='event[venue_name]'][data-venue-autocomplete-target='input']", count: 1
    assert_select "input[name='event[venue_id]'][data-venue-autocomplete-target='hidden']", count: 1
    assert_select ".venue-autocomplete[data-controller='venue-autocomplete']", count: 1
  end

  test "show populates ticket url with the frontend ticket url" do
    sign_in_as(@user)

    get backend_event_url(@published_event, status: "published")

    assert_response :success
    assert_select "h3", text: "Ticket"
    assert_select "input#ticket_sold_out_event_#{@published_event.id}", count: 0
    assert_includes response.body, "Ist nicht ausverkauft"
    assert_select "input#ticket_url_event_#{@published_event.id}[readonly][value='https://example.com/tickets/published']"
    assert_select "input#sks_sold_out_message_event_#{@published_event.id}[name='event[sks_sold_out_message]']"
    assert_select "input[name='event[ticket_url]']", count: 0
    assert_includes response.body, "Quelle: easyticket"
  end

  test "show renders sold out label from event sold_out" do
    sign_in_as(@user)
    event_offers(:published_one_offer).update!(sold_out: true)

    get backend_event_url(@published_event, status: "published")

    assert_response :success
    assert_includes response.body, "Ist ausverkauft"
    assert_not_includes response.body, "Ist nicht ausverkauft"
  end

  test "new redirects to inbox split layout" do
    sign_in_as(@user)

    get new_backend_event_url

    assert_response :redirect
    assert_includes response.redirect_url, "new=1"

    follow_redirect!

    assert_response :success
    assert_select ".backend-split", count: 1
    assert_select "turbo-frame#event_editor", count: 1
    assert_select "div#event_editor_panel", count: 1
    assert_select "#event_topbar_editor_actions button[form='editor_form_event']", text: "Save", count: 1
    assert_select "#event_topbar_editor_actions a.button", text: "Open", count: 0
    assert_select "a.button", text: "New", count: 0
  end

  test "turbo frame new shows the same event fields with read only promoter display" do
    sign_in_as(@user)

    get new_backend_event_url, headers: { "Turbo-Frame" => "event_editor" }

    assert_response :success
    assert_select "turbo-frame#event_editor", count: 1
    assert_no_match(/Event-Inbox/, response.body)
    assert_select "#event-editor-tab-event[aria-selected='true']", count: 1
    assert_select "#event-editor-tab-event-image[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-slider-images[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-presenters[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-llm-enrichment[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-settings[aria-selected='false']", count: 1
    assert_select "#event-editor-panel-event:not([hidden])", count: 1
    assert_select "#event-editor-panel-event-image[hidden]", count: 1
    assert_select "#event-editor-panel-slider-images[hidden]", count: 1
    assert_select "#event-editor-panel-presenters[hidden]", count: 1
    assert_select "#event-editor-panel-llm-enrichment[hidden]", count: 1
    assert_select "#event-editor-panel-settings[hidden]", count: 1
    assert_select "input[name='editor_tab'][value='event']", count: 1
    assert_select "input[name='event[doors_at]']"
    assert_select "input[name='event[homepage_url]']"
    assert_select "input[name='event[instagram_url]']"
    assert_select "input[name='event[facebook_url]']"
    assert_select "input[name='event[promoter_id]']", count: 0
    assert_select "label.form-label", text: "Promoter"
    assert_select "input[readonly]#promoter_display_event[value='RUSS Live']", count: 1
    assert_select "input[name='event[ticket_url]']"
    assert_select "input[name='event[ticket_sold_out]'][type='hidden'][value='0']"
    assert_select "input[name='event[ticket_sold_out]'][type='checkbox'][value='1']"
    assert_select "input[name='event[sks_sold_out_message]']"
    assert_select "input[name='event[support]']"
    assert_select "textarea[name='event[organizer_notes]']"
    assert_select "input[name='event[show_organizer_notes]'][type='checkbox']"
    assert_operator response.body.index('name="event[organizer_notes]"'), :<, response.body.index('name="event[show_organizer_notes]"')
    assert_select "#event-editor-panel-event input[name='event[highlighted]']", count: 0
    assert_select "#event-editor-panel-event input[name='event[promotion_banner]']", count: 0
    assert_select "#event-editor-panel-settings input[name='event[highlighted]'][type='checkbox'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner]'][type='checkbox'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_kicker_text]'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_cta_text]'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event_promotion_banner_image[promotion_banner_image_signed_id]'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event_promotion_banner_image[remove_promotion_banner_image]'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_image_copyright]'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_image_focus_x]'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_image_focus_y]'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_image_zoom]'][form='editor_form_event']", count: 1
    assert_select "#event-editor-panel-settings .event-image-crop-frame[data-grid-variant='promotion-banner']", count: 1
    assert_select "#event-editor-panel-settings select#event_image_grid_variant", count: 0
    assert_select "#event-editor-panel-event .editor-genre-section", count: 0
    assert_select "#event-editor-panel-event input[name='event[genre_ids][]']", count: 0
    assert_select "input[name='event_image[detail_hero_files][]'][type='file']"
    assert_select "input[name='event_image[sub_text]']"
    assert_select "select#event_image_grid_variant", count: 1
    assert_select "select#event_image_grid_variant[name]", count: 0
    assert_select "input[name='event_image[card_focus_x]'][value='50.0']"
    assert_select "input[name='event_image[card_focus_y]'][value='50.0']"
    assert_select "input[name='event_image[card_zoom]'][value='100.0']"
    assert_select "input[name='event_image[slider_files][]'][type='file']"
    assert_select "input[name='event_image[slider_alt_text]']"
    assert_select "[data-controller='event-image-preupload']"
    assert_select "[data-event-image-crop-preview-target='previewBox']", count: 2
    assert_includes response.body, "startDate.setHours(startDate.getHours()-1)"
    assert_includes response.body, "LLM-Enrichment ist für neue Events erst nach dem ersten Speichern verfügbar."
  end

  test "turbo frame new keeps requested presenters tab active" do
    sign_in_as(@user)
    create_presenter(name: "Alpha Presenter")

    get new_backend_event_url(editor_tab: "presenters"), headers: { "Turbo-Frame" => "event_editor" }

    assert_response :success
    assert_select "#event-editor-tab-event[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-presenters[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-event[hidden]", count: 1
    assert_select "#event-editor-panel-presenters:not([hidden])", count: 1
    assert_select "input[name='editor_tab'][value='presenters']", count: 1
    assert_select ".presenter-reference-items[data-controller='settings-sortable']", count: 1
  end

  test "turbo frame new keeps requested settings tab active" do
    sign_in_as(@user)

    get new_backend_event_url(editor_tab: "settings"), headers: { "Turbo-Frame" => "event_editor" }

    assert_response :success
    assert_select "#event-editor-tab-settings[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-settings:not([hidden])", count: 1
    assert_select "#event-editor-panel-event[hidden]", count: 1
    assert_select "input[name='editor_tab'][value='settings']", count: 1
    assert_select "#event-editor-panel-settings .editor-subsection", count: 2
    assert_select "#event-editor-panel-settings input[name='event_promotion_banner_image[promotion_banner_image_signed_id]'][form='editor_form_event']", count: 1
  end

  test "turbo frame new keeps requested llm enrichment tab active" do
    sign_in_as(@user)

    get new_backend_event_url(editor_tab: "llm_enrichment"), headers: { "Turbo-Frame" => "event_editor" }

    assert_response :success
    assert_select "#event-editor-tab-llm-enrichment[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-llm-enrichment:not([hidden])", count: 1
    assert_select "#event-editor-panel-event[hidden]", count: 1
    assert_select "input[name='editor_tab'][value='llm_enrichment']", count: 1
    assert_select "button", text: "LLM-Enrichment für dieses Event starten", count: 0
    assert_includes response.body, "LLM-Enrichment ist für neue Events erst nach dem ersten Speichern verfügbar."
  end

  test "slider image meta actions keep delete separate from meta form" do
    sign_in_as(@user)
    image = create_event_image(event: @event, purpose: EventImage::PURPOSE_SLIDER)

    get backend_events_url(status: "needs_review", event_id: @event.id)

    assert_response :success
    assert_select ".slider-image-editor-card .slider-image-meta-form", count: 1
    assert_select ".slider-image-editor-card .slider-image-meta-form[data-controller='autosave']", count: 0
    assert_select ".slider-image-editor-card .slider-image-meta-form input[name='event_image_updates[#{image.id}][alt_text]'][form='editor_form_event_#{@event.id}']", count: 1
    assert_select ".slider-image-editor-card .slider-image-meta-form input[name='event_image_updates[#{image.id}][sub_text]'][form='editor_form_event_#{@event.id}']", count: 1
    assert_select ".slider-image-editor-card .slider-image-meta-actions .button_to", count: 1
    assert_select ".slider-image-editor-card .slider-image-meta-form button", count: 0
    assert_select ".slider-image-editor-card .slider-image-meta-form input[type='submit']", count: 0
    assert_select ".slider-image-editor-card .slider-image-meta-form form", count: 0
  end

  test "top save persists slider image metadata from slider images tab" do
    sign_in_as(@user)
    image = create_event_image(event: @event, purpose: EventImage::PURPOSE_SLIDER, alt_text: "Alt", sub_text: "Sub")

    patch backend_event_url(@event), params: {
      event: {
        title: @event.title,
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        status: "needs_review"
      },
      event_image_updates: {
        image.id.to_s => {
          alt_text: "Neuer Alt-Text",
          sub_text: "Neue Subline"
        }
      },
      editor_tab: "slider_images",
      next_event_enabled: "0"
    }, as: :turbo_stream

    assert_response :success
    assert_equal "Neuer Alt-Text", image.reload.alt_text
    assert_equal "Neue Subline", image.reload.sub_text
    assert_includes response.body, "Event wurde gespeichert."
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
    assert_select "select#event_image_grid_variant", count: 1
    assert_select "select#event_image_grid_variant[name]", count: 0
    assert_select "input[name='event_image[card_focus_x]'][form='editor_form_event_#{@event.id}'][value='#{image.card_focus_x_value}']"
    assert_select "input[name='event_image[card_focus_y]'][form='editor_form_event_#{@event.id}'][value='#{image.card_focus_y_value}']"
    assert_select "input[name='event_image[card_zoom]'][form='editor_form_event_#{@event.id}'][value='#{image.card_zoom_value}']"
    assert_select "input#event_image_#{image.id}_card_focus_x[name]", count: 0
    assert_select "input#event_image_#{image.id}_card_focus_y[name]", count: 0
    assert_select "input#event_image_#{image.id}_card_zoom[name]", count: 0
    assert_select "[data-event-image-crop-preview-target='previewBox']", count: 2
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
    assert_select "select[name='merge_run_id'] option[value='all'][selected]", text: "Alle"
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

  test "change type filter is enabled when a merge run is selected" do
    sign_in_as(@user)

    merge_run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "merge",
      status: "succeeded",
      started_at: Time.zone.parse("2026-03-27 10:35:10"),
      finished_at: Time.zone.parse("2026-03-27 10:36:10")
    )

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      merge_run_id: merge_run.id,
      merge_change_type: "updated"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_select "select[name='merge_run_id'] option[selected][value='#{merge_run.id}']"
    assert_select "select[name='merge_change_type']:not([disabled])"
  end

  test "index shows only the five newest successful merge runs in the filter" do
    sign_in_as(@user)

    successful_runs = 6.times.map do |index|
      ImportRun.create!(
        import_source: import_sources(:one),
        source_type: "merge",
        status: "succeeded",
        started_at: Time.zone.parse("2026-03-27 10:00:00") + index.minutes,
        finished_at: Time.zone.parse("2026-03-27 10:00:30") + index.minutes
      )
    end
    failed_run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "merge",
      status: "failed",
      started_at: Time.zone.parse("2026-03-27 09:00:00"),
      finished_at: Time.zone.parse("2026-03-27 09:00:30")
    )
    running_run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "merge",
      status: "running",
      started_at: Time.zone.parse("2026-03-27 11:00:00")
    )

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_select "select[name='merge_run_id'] option", count: 6

    successful_runs.last(5).reverse_each do |run|
      assert_select "select[name='merge_run_id'] option[value='#{run.id}']", text: "Run ID ##{run.id}: #{run.started_at.strftime("%d.%m.%Y %H:%M:%S")}"
    end

    assert_select "select[name='merge_run_id'] option[value='#{successful_runs.first.id}']", count: 0
    assert_select "select[name='merge_run_id'] option[value='#{failed_run.id}']", count: 0
    assert_select "select[name='merge_run_id'] option[value='#{running_run.id}']", count: 0
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

  test "applies merge filters and shows import change badge for created events in selected merge run" do
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
      merge_run_id: merge_run.id,
      merge_change_type: "created"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_select ".status-badge-import-new", text: "New"
    assert_select ".status-badge-import-updated", count: 0
    assert_includes response.body, "Review Artist"
    assert_not_includes response.body, "Review Artist Two"
  end

  test "stale merge run selections fall back to all and disable change type" do
    sign_in_as(@user)

    runs = 6.times.map do |index|
      ImportRun.create!(
        import_source: import_sources(:one),
        source_type: "merge",
        status: "succeeded",
        started_at: Time.zone.parse("2026-03-27 08:00:00") + index.minutes,
        finished_at: Time.zone.parse("2026-03-27 08:00:30") + index.minutes
      )
    end

    post apply_filters_backend_events_url, params: {
      status: "needs_review",
      merge_run_id: runs.first.id,
      merge_change_type: "updated"
    }

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_select "select[name='merge_run_id'] option[selected][value='all']"
    assert_select "select[name='merge_change_type'][disabled]"
    assert_select "select[name='merge_change_type'] option[selected][value='all']"
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
        sks_sold_out_message: "Bitte beim Veranstalter nach Restkarten fragen",
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
    assert_equal "Bitte beim Veranstalter nach Restkarten fragen", @event.sks_sold_out_message
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
    presenter_one = create_presenter(name: "Alpha Presenter")
    presenter_two = create_presenter(name: "Beta Presenter")

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
            sks_sold_out_message: "Bitte beim Veranstalter melden",
            promoter_id: "10135",
            highlighted: "1",
            ticket_url: "https://tickets.example/manual-tour",
            event_info: "Lange Beschreibung",
            editor_notes: "Interne Notiz",
            status: "needs_review",
            genre_ids: [ genres(:pop).id.to_s ],
            presenter_ids: [ presenter_two.id.to_s, presenter_one.id.to_s ]
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
    assert_equal "Bitte beim Veranstalter melden", created.sks_sold_out_message
    assert_equal "382", created.promoter_id
    assert_equal "RUSS Live", created.promoter_name
    assert_predicate created, :highlighted?
    assert_equal "ready_for_publish", created.status
    assert_equal [ "Pop" ], created.genres.order(:name).pluck(:name)
    assert_equal [ presenter_two.id, presenter_one.id ], created.event_presenters.order(:position).pluck(:presenter_id)
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

  test "creates manual sold out offer without ticket url" do
    sign_in_as(@user)

    assert_difference("Event.count", 1) do
      assert_difference("EventOffer.count", 1) do
        post backend_events_url, params: {
          event: {
            artist_name: "Sold Out Artist",
            title: "Sold Out Tour",
            start_at: Time.zone.parse("2026-09-01 20:00:00"),
            venue: "Im Wizemann",
            city: "Stuttgart",
            promoter_id: "10135",
            ticket_sold_out: "1",
            status: "needs_review"
          }
        }
      end
    end

    created = Event.order(:id).last
    offer = created.manual_ticket_offer

    assert_equal "manual", offer.source
    assert_nil offer.ticket_url
    assert_equal true, offer.sold_out
    assert_nil created.public_ticket_offer
    assert_equal offer, created.editor_ticket_offer
  end

  test "create rejects invalid manual ticket url" do
    sign_in_as(@user)

    assert_no_difference("Event.count") do
      post backend_events_url, params: {
        event: {
          artist_name: "Invalid URL Artist",
          title: "Invalid URL Tour",
          start_at: Time.zone.parse("2026-09-02 20:00:00"),
          venue: "Im Wizemann",
          city: "Stuttgart",
          promoter_id: "10135",
          ticket_url: "not-a-url",
          status: "needs_review"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Ticket-URL muss mit http:// oder https:// beginnen."
    assert_select "input#ticket_url_event[value='not-a-url']"
  end

  test "update rejects invalid manual ticket url" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        title: @event.title,
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        ticket_url: "tickets-without-scheme",
        status: @event.status
      }
    }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, "Ticket-URL muss mit http:// oder https:// beginnen."
    assert_select "input#ticket_url_event_#{@event.id}[value='tickets-without-scheme']"
    assert_nil @event.reload.manual_ticket_offer
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

  test "update ignores submitted promoter id changes" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        promoter_id: "99999",
        title: "Review Event aktualisiert"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_equal @event.promoter_id, @event.reload.promoter_id
    assert_equal "Review Event aktualisiert", @event.title
  end

  test "create validation error keeps presenters tab active and preserves presenter order" do
    sign_in_as(@user)
    presenter_one = create_presenter(name: "Alpha Presenter")
    presenter_two = create_presenter(name: "Beta Presenter")

    assert_no_difference("Event.count") do
      post backend_events_url, params: {
        editor_tab: "presenters",
        event: {
          artist_name: "",
          title: "Manual Tour",
          start_at: Time.zone.parse("2026-08-18 20:00:00"),
          venue: "Im Wizemann",
          city: "Stuttgart",
          status: "needs_review",
          presenter_ids: [ presenter_two.id.to_s, presenter_one.id.to_s ]
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#event-editor-tab-presenters[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-presenters:not([hidden])", count: 1
    assert_select "input[name='editor_tab'][value='presenters']", count: 1
    assert_select "input[name='event[presenter_ids][]'][value='#{presenter_two.id}'][checked]", count: 1
    assert_select "input[name='event[presenter_ids][]'][value='#{presenter_one.id}'][checked]", count: 1
    assert_select "#event-editor-panel-presenters input[name='event[presenter_ids][]'][type='checkbox']", count: 2 do |inputs|
      assert_equal [ presenter_two.id.to_s, presenter_one.id.to_s ], inputs.map { |input| input["value"] }
    end
  end

  test "create stores settings fields from settings tab" do
    sign_in_as(@user)
    start_at = Time.zone.parse("2026-08-18 20:00:00")

    assert_difference("Event.count", 1) do
      post backend_events_url, params: {
        editor_tab: "settings",
        event: {
          artist_name: "Manual Artist",
          title: "Manual Tour",
          start_at: start_at,
          venue: "Im Wizemann",
          city: "Stuttgart",
          status: "needs_review",
          highlighted: "1",
          promotion_banner: "1",
          promotion_banner_kicker_text: "Szene Tipp",
          promotion_banner_cta_text: "Jetzt ansehen"
        }
      }
    end

    created = Event.order(:id).last
    assert_redirected_to backend_events_url(status: "needs_review", event_id: created.id)
    assert_predicate created, :highlighted?
    assert_predicate created, :promotion_banner?
    assert_equal "Szene Tipp", created.promotion_banner_kicker_text
    assert_equal "Jetzt ansehen", created.promotion_banner_cta_text
  end

  test "create validation error keeps settings tab active" do
    sign_in_as(@user)

    assert_no_difference("Event.count") do
      post backend_events_url, params: {
        editor_tab: "settings",
        event: {
          artist_name: "",
          title: "Manual Tour",
          start_at: Time.zone.parse("2026-08-18 20:00:00"),
          venue: "Im Wizemann",
          city: "Stuttgart",
          status: "needs_review",
          highlighted: "1",
          promotion_banner: "1"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#event-editor-tab-settings[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-settings:not([hidden])", count: 1
    assert_select "input[name='editor_tab'][value='settings']", count: 1
  end

  test "create validation error keeps llm enrichment tab active" do
    sign_in_as(@user)

    assert_no_difference("Event.count") do
      post backend_events_url, params: {
        editor_tab: "llm_enrichment",
        event: {
          artist_name: "",
          title: "Manual Tour",
          start_at: Time.zone.parse("2026-08-18 20:00:00"),
          venue: "Im Wizemann",
          city: "Stuttgart",
          status: "needs_review"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#event-editor-tab-llm-enrichment[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-llm-enrichment:not([hidden])", count: 1
    assert_select "input[name='editor_tab'][value='llm_enrichment']", count: 1
    assert_includes response.body, "LLM-Enrichment ist für neue Events erst nach dem ersten Speichern verfügbar."
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

  test "save preserves a scheduled publication date for unpublished events" do
    sign_in_as(@user)
    scheduled_time = 2.days.from_now.change(min: 45, sec: 0)

    patch backend_event_url(@event), params: {
      inbox_status: "needs_review",
      next_event_enabled: "0",
      event: {
        title: @event.title,
        artist_name: @event.artist_name,
        start_at: @event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @event.venue,
        city: @event.city,
        status: "needs_review",
        published_at: scheduled_time.strftime("%Y-%m-%dT%H:%M")
      }
    }, as: :turbo_stream

    assert_response :success
    assert_equal scheduled_time.change(usec: 0), @event.reload.published_at
    assert_equal "needs_review", @event.status
    assert_nil @event.published_by
    assert_includes response.body, "Event wurde gespeichert."
  end

  test "save clears a scheduled publication date for unpublished events" do
    sign_in_as(@user)
    @event.update!(published_at: 2.days.from_now.change(min: 45, sec: 0))

    patch backend_event_url(@event), params: {
      inbox_status: "needs_review",
      next_event_enabled: "0",
      event: {
        title: @event.title,
        artist_name: @event.artist_name,
        start_at: @event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @event.venue,
        city: @event.city,
        status: "needs_review",
        published_at: ""
      }
    }, as: :turbo_stream

    assert_response :success
    assert_nil @event.reload.published_at
    assert_nil @event.published_by
    assert_includes response.body, "Event wurde gespeichert."
  end

  test "updates event venue and shows venue notice" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        title: @event.title,
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue_name: "LKA Longhorn",
        city: @event.city,
        status: "needs_review"
      }
    }

    assert_redirected_to backend_events_url(status: "needs_review", event_id: @event.id)
    assert_equal venues(:lka_longhorn), @event.reload.venue_record
    assert_equal "Venue wurde gespeichert.", flash[:notice]
  end

  test "updates event venue via turbo stream and renders venue flash message" do
    sign_in_as(@user)

    patch backend_event_url(@event), params: {
      event: {
        title: @event.title,
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue_name: "LKA Longhorn",
        city: @event.city,
        status: "needs_review"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "Venue wurde gespeichert."
    assert_equal venues(:lka_longhorn), @event.reload.venue_record
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
    assert_nil @event.published_at
    assert_equal @user, @event.published_by
    assert_includes flash[:notice], "gespeichert und publiziert"
  end

  test "save and publish rejects an explicitly scheduled publication date" do
    sign_in_as(@user)
    scheduled_time = 2.days.from_now.change(min: 30, sec: 0)

    patch backend_event_url(@event), params: {
      event: {
        title: "Neu und geplant publiziert",
        artist_name: @event.artist_name,
        start_at: @event.start_at,
        venue: @event.venue,
        city: @event.city,
        status: "needs_review",
        published_at: scheduled_time.strftime("%Y-%m-%dT%H:%M")
      },
      save_and_publish: "1"
    }

    assert_response :unprocessable_entity
    assert_equal "needs_review", @event.reload.status
    assert_nil @event.published_at
    assert_includes response.body, "liegt in der Zukunft"
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

  test "editor does not render genre section" do
    sign_in_as(@user)

    get backend_event_url(@published_event)

    assert_response :success
    assert_select "#event-editor-panel-event .editor-genre-section", count: 0
    assert_select "#event-editor-panel-settings .editor-genre-section", count: 0
    assert_select "input[type='checkbox'][name='event[genre_ids][]']", count: 0
  end

  test "update stores selected genres when submitted" do
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

  test "update stores highlighted flag from settings tab" do
    sign_in_as(@user)

    patch backend_event_url(@published_event), params: {
      editor_tab: "settings",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        highlighted: "1"
      }
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @published_event.id)
    assert_predicate @published_event.reload, :highlighted?
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
    assert_select "#event-editor-tab-presenters[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-llm-enrichment[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-settings[aria-selected='false']", count: 1
    assert_no_match(/Letzter LLM-Enrichment-Run:/, response.body)
    assert_select "form[action='#{run_llm_enrichment_backend_event_path(@published_event)}'] button", text: "LLM-Enrichment für dieses Event starten"
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
    assert_select "#event-editor-tab-presenters[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-llm-enrichment[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-settings[aria-selected='false']", count: 1
    assert_select "#event-editor-panel-event-image[hidden]", count: 1
    assert_select "#event-editor-panel-slider-images[hidden]", count: 1
    assert_select "#event-editor-panel-presenters[hidden]", count: 1
    assert_select "#event-editor-panel-llm-enrichment[hidden]", count: 1
    assert_select "#event-editor-panel-settings[hidden]", count: 1
    assert_operator response.body.index('id="event-editor-tab-llm-enrichment"'), :<, response.body.index('id="event-editor-tab-settings"')
    assert_includes response.body, "Letzter LLM-Enrichment-Run: Montag, 02.03.2026 12:11"
    assert_select "form[action='#{run_llm_enrichment_backend_event_path(@published_event)}'] button", text: "LLM-Enrichment für dieses Event starten"
    assert_select "textarea[name='event[llm_enrichment_attributes][genre_list]']", count: 1
    assert_select "textarea[name='event[llm_enrichment_attributes][venue_description]']", count: 0
    assert_select "textarea[name='event[llm_enrichment_attributes][raw_response_json]']", count: 0
    assert_select "textarea[name='event[llm_enrichment_attributes][artist_description]']", count: 0
    assert_includes response.body, "&quot;event_description&quot;: &quot;LLM Event Beschreibung&quot;"
    assert_includes response.body, "&quot;genre&quot;: ["
  end

  test "editor shows event image and slider tabs without llm enrichment" do
    sign_in_as(@user)

    get backend_event_url(@published_event, editor_tab: "event_image")

    assert_response :success
    assert_select "#event-editor-tab-event[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-event-image[aria-selected='true']", count: 1
    assert_select "#event-editor-tab-slider-images[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-presenters[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-llm-enrichment[aria-selected='false']", count: 1
    assert_select "#event-editor-tab-settings[aria-selected='false']", count: 1
    assert_select "#event-editor-panel-event[hidden]", count: 1
    assert_select "#event-editor-panel-event-image:not([hidden])", count: 1
    assert_select "#event-editor-panel-slider-images[hidden]", count: 1
    assert_select "#event-editor-panel-presenters[hidden]", count: 1
    assert_select "#event-editor-panel-settings[hidden]", count: 1
    assert_select "input[name='editor_tab'][value='event_image']", count: 1
  end

  test "settings tab shows moved editor subsections" do
    sign_in_as(@user)

    get backend_event_url(@published_event, editor_tab: "settings")

    assert_response :success
    assert_select "#event-editor-tab-settings[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-settings:not([hidden])", count: 1
    assert_select "#event-editor-panel-event[hidden]", count: 1
    assert_select "#event-editor-panel-settings .editor-subsection", count: 2
    assert_select "#event-editor-panel-settings input[name='event[published_at]'][type='datetime-local']", count: 0
    assert_select "#event-editor-panel-settings input[name='event[highlighted]'][type='checkbox'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings h3", text: "Promotion Banner", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner]'][type='checkbox'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_kicker_text]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_cta_text]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_background_color]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[type='color']#event_promotion_banner_background_color_picker[form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings button[data-promotion-banner-color-target='eyedropper']", count: 1
    assert_select "#event-editor-panel-settings input[name='event_promotion_banner_image[promotion_banner_image_signed_id]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event_promotion_banner_image[remove_promotion_banner_image]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_image_copyright]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_image_focus_x]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_image_focus_y]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings input[name='event[promotion_banner_image_zoom]'][form='editor_form_event_#{@published_event.id}']", count: 1
    assert_select "#event-editor-panel-settings .event-image-crop-frame[data-grid-variant='promotion-banner']", count: 1
    assert_select "#event-editor-panel-settings select#event_image_grid_variant", count: 0
    assert_select "form#editor_form_event_#{@published_event.id} input[type='hidden'][name='event[promotion_banner]']", count: 0
    assert_select "form#editor_form_event_#{@published_event.id} input[type='hidden'][name='event[promotion_banner_kicker_text]']", count: 0
    assert_select "form#editor_form_event_#{@published_event.id} input[type='hidden'][name='event[promotion_banner_cta_text]']", count: 0
    assert_select "#event-editor-panel-settings .editor-genre-section", count: 0
  end

  test "editor can save an event promotion banner image from settings" do
    sign_in_as(@user)
    promotion_blob = create_uploaded_blob(filename: "event-promotion-banner.png", width: 1600, height: 900)

    patch backend_event_url(@published_event), params: {
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: @published_event.status,
        promotion_banner: "1",
        promotion_banner_kicker_text: "Empfehlung",
        promotion_banner_cta_text: "Jetzt ansehen",
        promotion_banner_background_color: "#18333A",
        promotion_banner_image_copyright: "Foto: Haus",
        promotion_banner_image_focus_x: "18",
        promotion_banner_image_focus_y: "72",
        promotion_banner_image_zoom: "145"
      },
      event_promotion_banner_image: {
        promotion_banner_image_signed_id: promotion_blob.signed_id,
        remove_promotion_banner_image: "0"
      },
      editor_tab: "settings",
      next_event_enabled: "0"
    }, as: :turbo_stream

    assert_response :success
    assert_predicate @published_event.reload.promotion_banner_image, :attached?
    assert_equal "Foto: Haus", @published_event.promotion_banner_image_copyright
    assert_equal 18.0, @published_event.promotion_banner_image_focus_x_value
    assert_equal 72.0, @published_event.promotion_banner_image_focus_y_value
    assert_equal 145.0, @published_event.promotion_banner_image_zoom_value
    assert_equal "#18333A", @published_event.promotion_banner_background_color
    assert_includes response.body, 'value="settings"'
  end

  test "llm enrichment tab shows empty state when no enrichment exists" do
    sign_in_as(@user)

    get backend_event_url(@published_event, editor_tab: "llm_enrichment")

    assert_response :success
    assert_select "#event-editor-tab-llm-enrichment[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-llm-enrichment:not([hidden])", count: 1
    assert_select "form[action='#{run_llm_enrichment_backend_event_path(@published_event)}'] button", text: "LLM-Enrichment für dieses Event starten"
    assert_select "textarea[name='event[llm_enrichment_attributes][genre_list]']", count: 0
    assert_includes response.body, "Für dieses Event gibt es noch kein LLM-Enrichment."
  end

  test "run llm enrichment starts a single event run" do
    sign_in_as(@user)

    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      post run_llm_enrichment_backend_event_url(@published_event), params: {
        status: "published",
        editor_tab: "llm_enrichment"
      }
    end

    run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last

    assert_equal "queued", run.status
    assert_equal "single_event", run.metadata["trigger_scope"]
    assert_equal @published_event.id, run.metadata["target_event_id"]
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.metadata["refresh_existing"])
    assert_redirected_to backend_events_url(status: "published", event_id: @published_event.id, editor_tab: "llm_enrichment")
    follow_redirect!
    assert_includes response.body, "LLM-Enrichment für dieses Event wurde gestartet."
  end

  test "run llm enrichment queues behind an active run and keeps llm tab active in turbo" do
    sign_in_as(@user)
    ImportRun.create!(
      import_source: import_sources(:two),
      status: "running",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: { "execution_started_at" => 1.minute.ago.iso8601 }
    )

    assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
      post run_llm_enrichment_backend_event_url(@published_event), params: {
        status: "published",
        editor_tab: "llm_enrichment"
      }, as: :turbo_stream
    end

    run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last

    assert_equal "queued", run.status
    assert_equal "single_event", run.metadata["trigger_scope"]
    assert_includes response.body, "LLM-Enrichment für dieses Event wurde zur Warteschlange hinzugefügt"
    assert_includes response.body, 'id="event-editor-tab-llm-enrichment"'
    assert_includes response.body, 'aria-selected="true"'
  end

  test "editor shows presenters tab with sortable selection list" do
    sign_in_as(@user)
    create_presenter(name: "Alpha Presenter")
    create_presenter(name: "Beta Presenter")

    get backend_event_url(@published_event, editor_tab: "presenters")

    assert_response :success
    assert_select "#event-editor-tab-presenters[aria-selected='true']", count: 1
    assert_select "#event-editor-panel-presenters:not([hidden])", count: 1
    assert_select "input[name='event[presenter_ids][]'][type='hidden'][value='']", count: 1
    assert_select ".presenter-reference-items[data-controller='settings-sortable']", count: 1
  end

  test "update stores presenter selection order from editor" do
    sign_in_as(@user)
    presenter_one = create_presenter(name: "Alpha Presenter")
    presenter_two = create_presenter(name: "Beta Presenter")

    patch backend_event_url(@published_event), params: {
      editor_tab: "presenters",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        presenter_ids: [ presenter_two.id.to_s, presenter_one.id.to_s ]
      }
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @published_event.id)
    assert_equal [ presenter_two.id, presenter_one.id ], @published_event.reload.event_presenters.order(:position).pluck(:presenter_id)
  end

  test "turbo update keeps presenters tab active after successful save" do
    sign_in_as(@user)
    presenter = create_presenter(name: "Gamma Presenter")

    patch backend_event_url(@published_event), params: {
      inbox_status: "published",
      next_event_enabled: "0",
      editor_tab: "presenters",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        presenter_ids: [ presenter.id.to_s ]
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'id="event-editor-tab-presenters"'
    assert_includes response.body, 'value="presenters"'
    assert_match(/id="event-editor-tab-presenters"[^>]*aria-selected="true"/, response.body)
  end

  test "validation error keeps presenters tab active" do
    sign_in_as(@user)
    presenter = create_presenter(name: "Delta Presenter")

    patch backend_event_url(@published_event), params: {
      inbox_status: "published",
      next_event_enabled: "0",
      editor_tab: "presenters",
      event: {
        title: @published_event.title,
        artist_name: "",
        start_at: @published_event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        presenter_ids: [ presenter.id.to_s ]
      }
    }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, 'id="event-editor-tab-presenters"'
    assert_includes response.body, 'value="presenters"'
    assert_match(/id="event-editor-tab-presenters"[^>]*aria-selected="true"/, response.body)
  end

  test "turbo update keeps settings tab active after successful save" do
    sign_in_as(@user)
    create_event_image(event: @published_event, purpose: EventImage::PURPOSE_DETAIL_HERO)

    patch backend_event_url(@published_event), params: {
      inbox_status: "published",
      next_event_enabled: "0",
      editor_tab: "settings",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        highlighted: "1",
        promotion_banner: "1",
        promotion_banner_kicker_text: "Szene Tipp",
        promotion_banner_cta_text: "Jetzt ansehen",
        promotion_banner_background_color: "18333a"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'id="event-editor-tab-settings"'
    assert_includes response.body, 'value="settings"'
    assert_match(/id="event-editor-tab-settings"[^>]*aria-selected="true"/, response.body)
    assert_predicate @published_event.reload, :highlighted?
    assert_predicate @published_event, :promotion_banner?
    assert_equal "Szene Tipp", @published_event.promotion_banner_kicker_text
    assert_equal "Jetzt ansehen", @published_event.promotion_banner_cta_text
    assert_equal "#18333A", @published_event.promotion_banner_background_color
  end

  test "update stores a scheduled publication date" do
    sign_in_as(@user)
    scheduled_time = 2.days.from_now.change(min: 15, sec: 0)

    patch backend_event_url(@published_event), params: {
      editor_tab: "settings",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        published_at: scheduled_time.strftime("%Y-%m-%dT%H:%M")
      }
    }

    assert_redirected_to backend_events_url(status: "ready_for_publish", event_id: @published_event.id)
    assert_equal "ready_for_publish", @published_event.reload.status
    assert_equal scheduled_time.change(usec: 0), @published_event.reload.published_at
  end

  test "update clears a scheduled publication date for published events" do
    sign_in_as(@user)
    @published_event.update!(published_at: 2.days.from_now.change(min: 15, sec: 0))

    patch backend_event_url(@published_event), params: {
      editor_tab: "settings",
      event: {
        title: @published_event.title,
        artist_name: @published_event.artist_name,
        start_at: @published_event.start_at,
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        published_at: ""
      }
    }

    assert_redirected_to backend_events_url(status: "published", event_id: @published_event.id)
    assert_nil @published_event.reload.published_at
    assert_equal users(:one), @published_event.published_by
  end

  test "validation error keeps settings tab active" do
    sign_in_as(@user)

    patch backend_event_url(@published_event), params: {
      inbox_status: "published",
      next_event_enabled: "0",
      editor_tab: "settings",
      event: {
        title: @published_event.title,
        artist_name: "",
        start_at: @published_event.start_at.strftime("%Y-%m-%dT%H:%M"),
        venue: @published_event.venue,
        city: @published_event.city,
        status: "published",
        highlighted: "1",
        promotion_banner: "1"
      }
    }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, 'id="event-editor-tab-settings"'
    assert_includes response.body, 'value="settings"'
    assert_match(/id="event-editor-tab-settings"[^>]*aria-selected="true"/, response.body)
    assert_includes response.body, "Artist name darf nicht leer sein"
  end

  test "update stores editable nested llm enrichment fields from editor" do
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
          event_description: "Aktualisierte kombinierte Event-Beschreibung",
          venue_external_url: "https://venue.example/updated",
          venue_address: "Venue Straße 12, Stuttgart",
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
    assert_equal "Aktualisierte kombinierte Event-Beschreibung", enrichment.event_description
    assert_equal "LLM Venue Beschreibung", enrichment.venue_description
    assert_equal "https://venue.example/updated", enrichment.venue_external_url
    assert_equal "Venue Straße 12, Stuttgart", enrichment.venue_address
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

  test "publish rejects events with a future publication date" do
    sign_in_as(@user)
    @event.update!(status: "ready_for_publish", published_at: 2.days.from_now.change(usec: 0))

    patch publish_backend_event_url(@event)

    assert_redirected_to backend_events_url(status: "ready_for_publish", event_id: @event.id)
    assert_equal "ready_for_publish", @event.reload.status
    assert_includes flash[:alert], "liegt in der Zukunft"
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
    assert_nil @event.published_at
  end

  test "bulk publish rejects a scheduled publication date" do
    sign_in_as(@user)
    scheduled_time = 4.days.from_now.change(usec: 0)
    @event.update!(published_at: scheduled_time)

    patch bulk_backend_events_url, params: {
      bulk_action: "publish",
      event_ids: [ @event.id ]
    }

    assert_redirected_to backend_events_url(status: "published")
    assert_equal "needs_review", @event.reload.status
    assert_equal scheduled_time, @event.published_at
    assert_includes flash[:alert], "liegt in der Zukunft"
  end

  test "bulk group action assigns a manual event series" do
    sign_in_as(@user)

    patch bulk_backend_events_url, params: {
      status: "needs_review",
      bulk_action: "group_as_series",
      event_ids: [ @event.id, @next_event.id ]
    }

    assert_redirected_to backend_events_url(status: "needs_review")
    assert @event.reload.event_series.manual?
    assert_equal @event.event_series_id, @next_event.reload.event_series_id
  end

  test "index shows event series badge for grouped events" do
    sign_in_as(@user)
    series = EventSeries.create!(origin: "manual", name: "Backend Reihe")
    @event.update!(event_series: series, event_series_assignment: "manual")
    @next_event.update!(event_series: series, event_series_assignment: "manual")

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_select "#events_list .status-badge-series", text: "Event-Reihe"
  end

  test "editor shows event series badge in header badges" do
    sign_in_as(@user)
    series = EventSeries.create!(origin: "manual", name: "Backend Reihe")
    @event.update!(event_series: series, event_series_assignment: "manual")
    @next_event.update!(event_series: series, event_series_assignment: "manual")

    get backend_events_url(status: "needs_review", event_id: @event.id)

    assert_response :success
    assert_select "#event_editor_panel .editor-header-badges .status-badge-series", text: "Event-Reihe"
  end

  test "editor does not show event series badge for single-event series" do
    sign_in_as(@user)
    series = EventSeries.create!(origin: "manual", name: "Singleton Reihe")
    @event.update!(event_series: series, event_series_assignment: "manual")

    get backend_events_url(status: "needs_review", event_id: @event.id)

    assert_response :success
    assert_select "#event_editor_panel .editor-header-badges .status-badge-series", count: 0
  end

  test "index does not show event series badge for single-event series" do
    sign_in_as(@user)
    series = EventSeries.create!(origin: "manual", name: "Singleton Reihe")
    @event.update!(event_series: series, event_series_assignment: "manual")

    get backend_events_url(status: "needs_review")

    assert_response :success
    assert_select "#events_list .status-badge-series", count: 0
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
      event_description: event_description,
      venue_description: "LLM Venue Beschreibung",
      genre: [ "Indie" ],
      model: "gpt-test",
      prompt_version: "v1",
      raw_response: {
        "event_description" => event_description,
        "genre" => [ "Indie" ]
      }
    )
  end

  def create_presenter(name:)
    presenter = Presenter.new(
      name: name,
      external_url: "https://example.com/#{name.parameterize}"
    )
    presenter.logo.attach(create_uploaded_blob(filename: "#{name.parameterize}.png"))
    presenter.save!
    presenter
  end
end
