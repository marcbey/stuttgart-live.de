require "test_helper"

class Public::EventPreviewContextTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    @events = [
      [ "preview-context-first", Time.zone.local(2026, 5, 1, 19, 30), venues(:lka_longhorn) ],
      [ "preview-context-second", Time.zone.local(2026, 5, 2, 21), venues(:im_wizemann) ]
    ].map do |slug, start_at, venue|
      Event.create!(slug: slug, source_fingerprint: "test::#{slug}", artist_name: "Preview Context Artist",
                    title: "Zwei Konzertabende", start_at: start_at, venue_record: venue,
                    city: "Stuttgart", status: "published", published_at: 1.day.ago)
    end
  end

  teardown { travel_back }

  test "search previews distinguish repeated artists by local date time and venue" do
    get search_overlay_events_path(q: "Preview Context Artist")

    assert_response :success
    assert_preview_context
  end

  test "saved dropdown previews distinguish repeated artists by local date time and venue" do
    get saved_lane_events_path, params: { slugs: @events.map(&:slug), mode: "dropdown" }

    assert_response :success
    assert_preview_context
    assert_select "button[data-action='design-preview-saved-dropdown#remove']", count: 2
  end

  test "empty search offers editing in the visible search field and all events" do
    get search_path(q: "Unfindbarer Konzertabend")

    assert_response :success
    assert_select ".search-results-empty" do
      assert_select "button[type='button'][data-public-search-focus]", text: "Suche ändern"
      assert_select "a[href=?]", all_stuttgart_lane_path, text: "Alle Events ansehen"
      assert_select "p", text: /dieses Wochenende/
    end
    assert_select "form[data-controller='public-search']", minimum: 2 do |forms|
      assert forms.all? { |form| form["data-action"].include?("click@document->public-search#focusFromRecovery") }
    end
  end

  test "empty live search offers editing and all events" do
    get search_overlay_events_path(q: "Unfindbarer Konzertabend")

    assert_response :success
    assert_select ".public-search-overlay-empty" do
      assert_select "button[type='button'][data-public-search-focus]", text: "Suche ändern"
      assert_select "a[href=?]", all_stuttgart_lane_path, text: "Alle Events ansehen"
      assert_select "p", text: /dieses Wochenende/
    end
  end

  test "empty venue suggestions offer a way to continue searching" do
    get search_overlay_events_path(q: "heute im Unfindbaren Konzertsaal")

    assert_response :success
    assert_select ".public-search-overlay-empty" do
      assert_select "h2", text: "Keine Venue gefunden"
      assert_select "button[data-public-search-focus]", text: "Suche ändern"
      assert_select "a[href=?]", all_stuttgart_lane_path, text: "Alle Events ansehen"
    end
  end

  test "saved events explains browser storage outside the javascript fallback" do
    get saved_events_path

    assert_response :success
    assert_select ".saved-events-page-storage-note", text: "Deine Merkliste wird in diesem Browser gespeichert."
    assert_select "noscript .saved-events-page-storage-note", count: 0
    assert_select "button[data-action='design-preview-saved-dropdown#share']", count: 1
  end

  private

  def assert_preview_context
    [ [ @events.first, "01.05.2026 · 19:30 Uhr", "LKA Longhorn" ],
      [ @events.last, "02.05.2026 · 21:00 Uhr", "Im Wizemann" ] ].each do |event, date_time, venue|
      assert_select "a.public-search-result[href^=?]", event_path(event.slug), count: 1 do
        assert_select ".public-search-result-copy time[datetime=?]", event.start_at.iso8601, text: date_time
        assert_select ".public-search-result-copy .public-search-result-venue", text: venue
      end
    end
  end
end
