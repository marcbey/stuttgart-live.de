require "test_helper"

class Public::EventPaginationTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    setting = AppSetting.find_or_initialize_by(key: AppSetting::SKS_PROMOTER_IDS_KEY)
    setting.update!(value: [ "10135", "10136", "382" ])
    AppSetting.reset_cache!
  end

  teardown do
    travel_back
    AppSetting.reset_cache!
  end

  test "fixed lanes bound their first response and continue without repeating series" do
    series = EventSeries.create!(origin: "manual", name: "Paginierte Reihe")
    events = 25.times.map do |index|
      event = create_event(index: index)
      event.update!(highlighted: true, promoter_id: AppSetting.sks_promoter_ids.first, min_price: 25)
      event.event_offers.create!(source: "reservix", source_event_id: event.slug, ticket_url: "https://example.test/#{event.slug}")
      event
    end
    events.last.update!(event_series: series, event_series_assignment: "manual")
    events.first.update!(event_series: series, event_series_assignment: "manual")

    %w[/tagestipp /unter-30 /highlights /russ-live].each do |path|
      get path, params: { filter: "all" }
      assert_response :success
      document = Nokogiri::HTML.parse(response.body)
      section = document.at_css("section.lane-page-section")
      assert_equal 20, section.css("#lane-event-grid article.design-preview-card").size, path
      cursor = section["data-lane-page-cursor-value"]
      assert_predicate cursor, :present?, path
      first_titles = section.css("#lane-event-grid .design-preview-card-title").map { |node| node.text.squish }

      get section["data-lane-page-url-value"], params: { lane: section["data-lane-page-lane-value"], cursor: cursor, mode: "design_cards", per_page: 20 }
      assert_response :success
      second_titles = Nokogiri::HTML.parse(response.body).css(".design-preview-card-title").map { |node| node.text.squish }
      assert_empty first_titles & second_titles, path
      assert_includes response.body, events[23].artist_name
      assert_not_includes response.body, events.last.artist_name
    end
  end

  test "tagestipp only shows the current local date on every surface" do
    today = create_event(index: 0)
    tomorrow = create_event(index: 1, start_at: Time.zone.tomorrow.beginning_of_day)
    get "/tagestipp", params: { event_date: Time.zone.tomorrow.iso8601 }
    assert_response :success
    grid = Nokogiri::HTML.parse(response.body).at_css("#lane-event-grid")
    assert_includes grid.text, today.artist_name
    assert_not_includes grid.text, tomorrow.artist_name

    get root_url
    assert_response :success
    section = Nokogiri::HTML.parse(response.body).at_css(".design-preview-tagestipp-lane")
    assert_includes section.text, today.artist_name
    assert_not_includes section.text, tomorrow.artist_name

    get homepage_lane_events_url(lane: "tagestipp", event_date: Time.zone.tomorrow.iso8601)
    assert_response :success
    assert_includes response.body, today.artist_name
    assert_not_includes response.body, tomorrow.artist_name
  end

  test "search retains full count and every matching term across ranked cursor pages" do
    series = EventSeries.create!(origin: "manual", name: "Suchreihe")
    events = 25.times.map { |index| create_event(index: index, start_at: (index + 1).days.from_now) }
    events.first.update!(event_series: series, event_series_assignment: "manual")
    events[22].update!(event_series: series, event_series_assignment: "manual")
    events.last.update!(highlighted: true)

    get search_url(q: "Pagination Artist", filter: "all")
    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    assert_includes document.at_css(".lane-header-meta").text, "25 Ergebnisse"
    cards = document.css("#event-grid article.design-preview-card")
    assert_equal 20, cards.size
    assert_includes cards.first.text, events.last.artist_name
    section = document.at_css("section.search-results-section")
    cursor = section["data-lane-page-cursor-value"]
    assert_predicate cursor, :present?
    initial_titles = cards.map { |node| node.at_css(".design-preview-card-title").text.squish }

    get section["data-lane-page-url-value"], params: { lane: "search", cursor: cursor, mode: "design_cards", per_page: 20 }
    assert_response :success
    continuation_titles = Nokogiri::HTML.parse(response.body).css(".design-preview-card-title").map { |node| node.text.squish }
    assert_equal 25, (initial_titles + continuation_titles).size
    assert_equal events.map(&:artist_name).sort, (initial_titles + continuation_titles).sort
    assert_predicate response.headers["X-Homepage-Lane-Next-Cursor"], :blank?

    get homepage_lane_events_url(lane: "search", q: "Another query", filter: "all", cursor: cursor)
    assert_response :bad_request
    get homepage_lane_events_url(lane: "search", q: "Pagination Artist", filter: "sks", cursor: cursor)
    assert_response :bad_request
    get homepage_lane_events_url(lane: "search", q: "Pagination Artist", filter: "all", event_date: Time.zone.tomorrow.iso8601, cursor: cursor)
    assert_response :bad_request
  end

  private

  def create_event(index:, start_at: Time.zone.today.beginning_of_day + 18.hours + index.minutes)
    Event.create!(slug: "pagination-#{index}", source_fingerprint: "test::pagination::#{index}", title: "Pagination Title #{index}",
                  artist_name: "Pagination Artist #{index}", start_at: start_at, venue: "Club Zentral", city: "Stuttgart",
                  status: "published", published_at: 1.day.ago, source_snapshot: {})
  end
end
