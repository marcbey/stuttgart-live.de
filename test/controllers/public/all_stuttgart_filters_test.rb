require "test_helper"

class Public::AllStuttgartFiltersTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2030, 7, 30, 12)
    @events = (-1..22).map do |offset|
      Event.create!(
        source_fingerprint: "test::all-stuttgart-default::#{offset}",
        artist_name: "Chronological Artist #{offset}",
        title: "Chronological Event #{offset}",
        start_at: offset.days.from_now.change(hour: 9),
        venue_record: venues(:lka_longhorn),
        city: "Stuttgart",
        status: "published",
        published_at: 2.days.ago,
        genres: [ genres(:rock) ]
      )
    end
  end

  teardown { travel_back }

  test "homepage filters open the matching all Stuttgart list without an all button" do
    get root_path

    assert_response :success
    assert_select ".design-preview-filterbar--homepage[hidden]", count: 1
    assert_select ".design-preview-filterbar--homepage .design-preview-filter-all", count: 0
    assert_select ".design-preview[data-design-preview-filterbar-destination-value=?]", all_stuttgart_lane_path
    assert_select ".design-preview-filterbar--homepage .all-stuttgart-genre-menu a[href=?]",
                  all_stuttgart_lane_path(event_genre: genres(:rock).slug), text: genres(:rock).name
    assert_select ".design-preview-filterbar--homepage .all-stuttgart-location-menu a[href=?]",
                  all_stuttgart_lane_path(event_location: venues(:lka_longhorn).name), text: venues(:lka_longhorn).name
    month_path = css_select(".design-preview-filterbar--homepage .design-preview-month-menu a").find do |link|
      link["href"] == all_stuttgart_lane_path(event_month: "2030-08")
    end&.[]("href")
    assert_not_nil month_path

    get month_path

    assert_response :success
    assert_equal @events.drop(3).first(20).map(&:artist_name), row_titles
    assert_select ".design-preview-filter-month", text: "August 2030"
  end

  test "unfiltered list starts today and paginates chronologically across months" do
    get all_stuttgart_lane_path

    assert_response :success
    assert_select ".all-stuttgart-event-header h1", text: "alles aus stuttgart"
    assert_select ".design-preview-filter-month", text: "Monat"
    assert_select ".all-stuttgart-view-switch a[aria-label='Listenansicht'][aria-current='page']", count: 1
    assert_select ".all-stuttgart-event-section .design-preview-card", count: 0
    assert_select ".design-preview-filter-all[aria-current='page'][href=?]", all_stuttgart_lane_path, text: "Alles"
    expected = @events.drop(1)
    assert_equal expected.first(20).map(&:artist_name), row_titles

    section = css_select(".all-stuttgart-event-section").first
    assert_not_includes section["data-lane-page-url-value"], "event_month"
    get homepage_lane_events_path(
      lane: "all_stuttgart", mode: "all_stuttgart_rows", per_page: 20,
      cursor: section["data-lane-page-cursor-value"]
    )

    assert_response :success
    assert_equal expected.drop(20).map(&:artist_name), row_titles
  end

  test "month selection can be reset to all upcoming events" do
    get all_stuttgart_lane_path(event_month: "2030-08", event_genre: genres(:rock).slug)

    assert_response :success
    assert_select ".design-preview-filter-month", text: "August 2030"
    assert_equal @events.drop(3).first(20).map(&:artist_name), row_titles
    assert_select ".design-preview-filter-all[aria-current]", count: 0
    reset_path = css_select(".design-preview-filter-all").first["href"]

    get reset_path

    assert_response :success
    assert_select ".design-preview-filter-month", text: "Monat"
    assert_select ".all-stuttgart-active-filter-chip", count: 0
    assert_equal @events.drop(1).first(20).map(&:artist_name), row_titles
  end

  test "genre filtering without a month keeps events across months" do
    get all_stuttgart_lane_path(event_genre: genres(:rock).slug)

    assert_response :success
    assert_select ".design-preview-filter-month", text: "Monat"
    assert_select ".design-preview-month-menu a[href*='event_genre=rock']", minimum: 1
    assert_equal @events.drop(1).first(20).map(&:artist_name), row_titles
  end

  test "grid view renders and paginates the same chronological events" do
    get all_stuttgart_lane_path(view: "grid")

    assert_response :success
    assert_select ".all-stuttgart-view-switch a[aria-label='Kachelansicht'][aria-current='page']", count: 1
    assert_select ".all-stuttgart-event-list", count: 0
    assert_select ".design-preview-list-card-grid[data-lane-page-target='grid']", count: 1
    assert_equal @events.drop(1).first(20).map(&:artist_name), css_select(".design-preview-card-title").map(&:text)
    assert_select ".design-preview-month-menu a[href*='view=grid']", minimum: 1
    assert_select ".design-preview-filterbar .all-stuttgart-genre-menu a[href*='view=grid']", minimum: 1
    assert_select ".design-preview-filterbar .all-stuttgart-location-menu a[href*='view=grid']", minimum: 1

    section = css_select(".all-stuttgart-event-section").first
    assert_equal "design_cards", section["data-lane-page-card-mode-value"]
    get homepage_lane_events_path(
      lane: "all_stuttgart", mode: "design_cards", per_page: 20,
      cursor: section["data-lane-page-cursor-value"]
    )

    assert_response :success
    assert_equal @events.drop(21).map(&:artist_name), css_select(".design-preview-card-title").map(&:text)
  end

  test "view switching preserves filters and resetting filters preserves the chosen view" do
    filter_params = {
      event_month: "2030-07", event_date: "2030-07-30",
      event_genre: genres(:rock).slug, event_location: venues(:lka_longhorn).name
    }
    get all_stuttgart_lane_path(**filter_params, view: "grid")

    assert_response :success
    list_path = css_select(".all-stuttgart-view-switch a[aria-label='Listenansicht']").first["href"]
    assert_equal filter_params.stringify_keys, Rack::Utils.parse_query(URI.parse(list_path).query)
    assert_select ".design-preview-card-title", text: @events.second.artist_name, count: 1
    reset_path = css_select(".design-preview-filter-all").first["href"]

    get list_path

    assert_response :success
    assert_equal [ @events.second.artist_name ], row_titles
    assert_select ".all-stuttgart-view-switch a[aria-label='Listenansicht'][aria-current='page']", count: 1

    get reset_path

    assert_response :success
    assert_select ".design-preview-card", count: 20
    assert_select ".all-stuttgart-active-filter-chip", count: 0
    assert_select ".design-preview-filter-month", text: "Monat"
  end

  test "date ranges include both boundary days across months and survive view and genre changes" do
    @events[4].update!(start_at: Time.zone.local(2030, 8, 2, 23, 59))
    get all_stuttgart_lane_path(event_date: "2030-07-30", event_date_end: "2030-08-02", event_month: "2030-07")

    assert_response :success
    assert_equal @events[1..4].map(&:artist_name), row_titles
    assert_select ".all-stuttgart-event-header h1", text: "30. Juli 2030 – 2. August 2030"
    assert_select ".all-stuttgart-event-list-head span", text: "Tag", count: 1
    assert_select ".design-preview-filter-month", text: "Monat"
    assert_select ".design-preview-month-menu a[href*='event_date']", count: 0
    assert_select ".design-preview-filterbar .all-stuttgart-location-menu a[href*='event_date_end=2030-08-02']", minimum: 1
    genre_path = css_select(".design-preview-filterbar .all-stuttgart-genre-menu a[href*='event_genre=rock']").first["href"]
    clear_path = css_select(".all-stuttgart-active-filter-chip").first["href"]

    get genre_path

    assert_response :success
    assert_equal @events[1..4].map(&:artist_name), row_titles
    get css_select(".all-stuttgart-view-switch a[aria-label='Kachelansicht']").first["href"]

    assert_response :success
    assert_equal @events[1..4].map(&:artist_name), css_select(".design-preview-card-title").map(&:text)

    get clear_path

    assert_response :success
    assert_select ".all-stuttgart-active-filter-chip", count: 0
    assert_equal @events.drop(1).first(20).map(&:artist_name), row_titles
  end

  test "date range pagination preserves the end date and rejects a cursor from another range" do
    range = { event_date: "2030-07-30", event_date_end: "2030-08-21" }
    get all_stuttgart_lane_path(**range)

    assert_response :success
    section = css_select(".all-stuttgart-event-section").first
    assert_includes section["data-lane-page-url-value"], "event_date_end=2030-08-21"
    page_params = range.merge(lane: "all_stuttgart", mode: "all_stuttgart_rows", cursor: section["data-lane-page-cursor-value"], per_page: 20)

    get homepage_lane_events_path(**page_params)

    assert_response :success
    assert_equal @events.drop(21).map(&:artist_name), row_titles
    assert_select ".all-stuttgart-event-day--time", count: 0

    get homepage_lane_events_path(**page_params.merge(event_date_end: "2030-08-20"))

    assert_response :bad_request
  end

  test "invalid or reversed range ends fall back to the selected single day" do
    [ "invalid", "2030-02-30", "2030-07-29", "2030-07-30" ].each do |end_date|
      get all_stuttgart_lane_path(event_date: "2030-07-30", event_date_end: end_date)

      assert_response :success
      assert_equal [ @events.second.artist_name ], row_titles
      assert_select ".all-stuttgart-event-list-head span", text: "Uhrzeit", count: 1
    end
  end

  private

  def row_titles
    css_select(".all-stuttgart-event-title a").map(&:text)
  end
end
