require "test_helper"

class Public::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @published_event = events(:published_one)
    @past_published_event = events(:published_past_one)
    @user = users(:one)
  end

  test "index is publicly accessible" do
    get events_url(filter: "all")

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Events"
    assert_includes response.body, "Published Artist"
    assert_not_includes response.body, "Past Artist"
    assert_not_includes response.body, "Review Artist"
    assert_not_includes response.body, "event-card-status-select"
    assert_select ".event-card-genre", count: 0
    assert_select ".genre-grid .genre-tile", count: Genre.count
    assert_select ".genre-grid .genre-tile-link[href*='genre=schlager']", text: "Schlager"
    assert_select ".genre-grid .genre-tile-link[href*='genre=hiphop']", text: "Hip-Hop"
    assert_select ".genre-slider-track", count: 0
    assert_select "turbo-frame#genre-events-panel", count: 1
  end

  test "index expands a genre panel with matching events" do
    pop_event = Event.create!(
      slug: "genre-panel-pop-event",
      source_fingerprint: "test::public::genre-panel::pop",
      title: "Genre Panel Pop Event",
      artist_name: "Genre Pop Artist",
      start_at: 18.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    pop_event.genres << genres(:pop)

    get events_url(genre: "rock")

    assert_response :success
    assert_select "turbo-frame#genre-events-panel .genre-events-panel-title", text: "Rock"
    assert_select "turbo-frame#genre-events-panel .event-listing-card", text: /#{Regexp.escape(@published_event.artist_name)}/
    assert_select "turbo-frame#genre-events-panel .event-listing-card", text: /#{Regexp.escape(pop_event.artist_name)}/, count: 0
    assert_select ".genre-grid .genre-tile-link[href*='genre=rock'][aria-expanded='true']"
  end

  test "genre panel searches across all visible events regardless of selected date" do
    selected_date = 12.days.from_now.to_date

    other_promoter_rock_event = Event.create!(
      slug: "genre-panel-other-promoter-rock",
      source_fingerprint: "test::public::genre-panel::other-promoter-rock",
      title: "Genre Panel Other Promoter Rock Event",
      artist_name: "Genre Other Promoter Rock Artist",
      start_at: 25.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      promoter_id: "99999",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    other_promoter_rock_event.genres << genres(:rock)

    same_day_pop_event = Event.create!(
      slug: "genre-panel-same-day-pop",
      source_fingerprint: "test::public::genre-panel::same-day-pop",
      title: "Genre Panel Same Day Pop Event",
      artist_name: "Genre Same Day Pop Artist",
      start_at: selected_date.in_time_zone.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    same_day_pop_event.genres << genres(:pop)

    get events_url(genre: "rock", event_date: selected_date.iso8601)

    assert_response :success
    assert_select "turbo-frame#genre-events-panel .event-listing-card", text: /#{Regexp.escape(@published_event.artist_name)}/
    assert_select "turbo-frame#genre-events-panel .event-listing-card", text: /#{Regexp.escape(other_promoter_rock_event.artist_name)}/
    assert_select "turbo-frame#genre-events-panel .event-listing-card", text: /#{Regexp.escape(same_day_pop_event.artist_name)}/, count: 0
  end

  test "genre frame request renders only the genre panel" do
    get events_url(genre: "rock"), headers: { "Turbo-Frame" => "genre-events-panel" }

    assert_response :success
    assert_select "turbo-frame#genre-events-panel", count: 1
    assert_select "turbo-frame#genre-events-panel .genre-events-panel-title", text: "Rock"
    assert_select "section.public-shell", count: 0
    assert_no_match(/Alle Veranstaltungen in Stuttgart/, response.body)
  end

  test "index hides future unpublished events for guests" do
    hidden_event = Event.create!(
      slug: "guest-hidden-draft-event",
      source_fingerprint: "test::public::guest-hidden-draft",
      title: "Guest Hidden Draft Event",
      artist_name: "Hidden Draft Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      status: "needs_review",
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success
    assert_not_includes response.body, hidden_event.artist_name
  end

  test "index shows future unpublished events in search results for authenticated users" do
    hidden_event = Event.create!(
      slug: "auth-visible-draft-event",
      source_fingerprint: "test::public::auth-visible-draft",
      title: "Auth Visible Draft Event",
      artist_name: "Auth Visible Draft Search Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      status: "needs_review",
      source_snapshot: {}
    )
    matching_published_event = Event.create!(
      slug: "auth-visible-published-search-event",
      source_fingerprint: "test::public::auth-visible-search::published",
      title: "Auth Visible Published Search Event",
      artist_name: "Auth Visible Draft Search Published",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    sign_in_as(@user)

    get events_url(filter: "all", q: "Auth Visible Draft Search")

    assert_response :success
    assert_includes response.body, hidden_event.artist_name
    assert_includes response.body, matching_published_event.artist_name
    assert_includes response.body, "event-card-status-select"
  end

  test "index shows only published events in homepage sections for authenticated users" do
    sign_in_as(@user)

    published_highlight = Event.create!(
      slug: "auth-homepage-published-highlight",
      source_fingerprint: "test::public::auth-homepage::published-highlight",
      title: "Auth Homepage Published Highlight",
      artist_name: "Auth Homepage Published Highlight Artist",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      primary_source: "eventim",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    unpublished_highlight = Event.create!(
      slug: "auth-homepage-unpublished-highlight",
      source_fingerprint: "test::public::auth-homepage::unpublished-highlight",
      title: "Auth Homepage Unpublished Highlight",
      artist_name: "Auth Homepage Unpublished Highlight Artist",
      start_at: 11.days.from_now.change(hour: 21, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      primary_source: "eventim",
      status: "needs_review",
      source_snapshot: {}
    )

    published_slider = Event.create!(
      slug: "auth-homepage-published-slider",
      source_fingerprint: "test::public::auth-homepage::published-slider",
      title: "Auth Homepage Published Slider",
      artist_name: "Auth Homepage Published Slider Artist",
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Theaterhaus",
      city: "Stuttgart",
      promoter_id: "99999",
      primary_source: "reservix",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    unpublished_slider = Event.create!(
      slug: "auth-homepage-unpublished-slider",
      source_fingerprint: "test::public::auth-homepage::unpublished-slider",
      title: "Auth Homepage Unpublished Slider",
      artist_name: "Auth Homepage Unpublished Slider Artist",
      start_at: 12.days.from_now.change(hour: 21, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: "99999",
      primary_source: "reservix",
      status: "needs_review",
      source_snapshot: {}
    )

    published_tagestipp = Event.create!(
      slug: "auth-homepage-published-tagestipp",
      source_fingerprint: "test::public::auth-homepage::published-tagestipp",
      title: "Auth Homepage Published Tagestipp",
      artist_name: "Auth Homepage Published Tagestipp Artist",
      start_at: Time.zone.today.in_time_zone.change(hour: 20, min: 0, sec: 0),
      venue: "Club Cann",
      city: "Stuttgart",
      promoter_id: "99999",
      primary_source: "eventim",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    unpublished_tagestipp = Event.create!(
      slug: "auth-homepage-unpublished-tagestipp",
      source_fingerprint: "test::public::auth-homepage::unpublished-tagestipp",
      title: "Auth Homepage Unpublished Tagestipp",
      artist_name: "Auth Homepage Unpublished Tagestipp Artist",
      start_at: Time.zone.today.in_time_zone.change(hour: 21, min: 0, sec: 0),
      venue: "Club Zentral",
      city: "Stuttgart",
      promoter_id: "99999",
      primary_source: "eventim",
      status: "needs_review",
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    highlights_section = document.css("section.home-featured-section").find do |section|
      section.at_css("h2")&.text == "Highlights"
    end
    all_events_section = document.css("section.home-slider-section").find do |section|
      section.at_css("h2")&.text == "Alle Veranstaltungen in Stuttgart"
    end
    tagestipp_section = document.css("section.home-slider-section").find do |section|
      section.at_css("h2")&.text == "Tagestipp"
    end

    assert highlights_section.present?, "expected Highlights section to be rendered"
    assert all_events_section.present?, "expected all events section to be rendered"
    assert tagestipp_section.present?, "expected Tagestipp section to be rendered"

    highlight_names = highlights_section.css(".home-featured-track .event-card-copy h2").map(&:text)
    all_event_names = all_events_section.css(".home-slider-card-name").map(&:text)
    tagestipp_names = tagestipp_section.css(".home-slider-card-name").map(&:text)

    assert_includes highlight_names, published_highlight.artist_name
    assert_not_includes highlight_names, unpublished_highlight.artist_name
    assert_includes all_event_names, published_slider.artist_name
    assert_not_includes all_event_names, unpublished_slider.artist_name
    assert_includes tagestipp_names, published_tagestipp.artist_name
    assert_not_includes tagestipp_names, unpublished_tagestipp.artist_name
  end

  test "index defaults to SKS filter" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)

    sks_event = Event.create!(
      slug: "default-sks-event",
      source_fingerprint: "test::default::sks",
      title: "Default SKS Event",
      artist_name: "Default SKS Artist",
      start_at: future_start,
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "382",
      source_snapshot: {}
    )

    non_sks_event = Event.create!(
      slug: "default-non-sks-event",
      source_fingerprint: "test::default::non-sks",
      title: "Default Non SKS Event",
      artist_name: "Default Non SKS Artist",
      start_at: future_start + 1.hour,
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "99999",
      source_snapshot: {}
    )

    get events_url

    assert_response :success
    assert_includes response.body, sks_event.artist_name
    assert_select ".home-featured-track", text: /#{Regexp.escape(sks_event.artist_name)}/
    assert_select ".home-featured-track", text: /#{Regexp.escape(non_sks_event.artist_name)}/, count: 0
  end

  test "index includes promoter 10136 in homepage highlights" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)

    highlighted_event = Event.create!(
      slug: "homepage-highlight-promoter-10136",
      source_fingerprint: "test::homepage::highlight::10136",
      title: "Homepage Highlight Promoter 10136",
      artist_name: "Highlight Promoter 10136 Artist",
      start_at: future_start,
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "10136",
      source_snapshot: {}
    )

    get events_url

    assert_response :success
    assert_select ".home-featured-track", text: /#{Regexp.escape(highlighted_event.artist_name)}/
  end

  test "index sorts highlights chronologically by start_at" do
    later_event = Event.create!(
      slug: "homepage-highlight-later",
      source_fingerprint: "test::homepage::highlight::later",
      title: "Homepage Highlight Later",
      artist_name: "Highlight Later Artist",
      start_at: 12.days.from_now.change(hour: 21, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      source_snapshot: {}
    )

    earlier_event = Event.create!(
      slug: "homepage-highlight-earlier",
      source_fingerprint: "test::homepage::highlight::earlier",
      title: "Homepage Highlight Earlier",
      artist_name: "Highlight Earlier Artist",
      start_at: 12.days.from_now.change(hour: 18, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: Event::SKS_PROMOTER_IDS.second,
      source_snapshot: {}
    )

    middle_event = Event.create!(
      slug: "homepage-highlight-middle",
      source_fingerprint: "test::homepage::highlight::middle",
      title: "Homepage Highlight Middle",
      artist_name: "Highlight Middle Artist",
      start_at: 12.days.from_now.change(hour: 19, min: 30, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: Event::SKS_PROMOTER_IDS.last,
      source_snapshot: {}
    )

    get events_url

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    highlights_section = document.css("section.home-featured-section").find do |section|
      section.at_css("h2")&.text == "Highlights"
    end

    assert highlights_section.present?, "expected Highlights section to be rendered"

    names = highlights_section.css(".home-featured-track .event-card-copy h2").map(&:text)

    assert_equal [ earlier_event.artist_name, middle_event.artist_name, later_event.artist_name ], names.first(3)
  end

  test "index shows only reservix events in the all events slider" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)

    reservix_event = Event.create!(
      slug: "reservix-home-slider-event",
      source_fingerprint: "test::homepage::reservix::slider",
      title: "Reservix Homepage Slider Event",
      artist_name: "Reservix Slider Artist",
      start_at: future_start,
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      source_snapshot: {}
    )

    eventim_event = Event.create!(
      slug: "eventim-home-slider-event",
      source_fingerprint: "test::homepage::eventim::slider",
      title: "Eventim Homepage Slider Event",
      artist_name: "Eventim Slider Artist",
      start_at: future_start + 1.hour,
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )

    10.times do |index|
      Event.create!(
        slug: "reservix-home-slider-filler-#{index}",
        source_fingerprint: "test::homepage::reservix::filler::#{index}",
        title: "Reservix Homepage Filler #{index}",
        artist_name: "Reservix Filler Artist #{index}",
        start_at: future_start + index.minutes,
        venue: "Venue #{index}",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        primary_source: "reservix",
        source_snapshot: {}
      )
    end

    late_reservix_event = Event.create!(
      slug: "reservix-home-slider-late-event",
      source_fingerprint: "test::homepage::reservix::late",
      title: "Reservix Homepage Late Event",
      artist_name: "Reservix Late Artist",
      start_at: future_start + 2.hours,
      venue: "Late Hall",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success
    assert_select "section.home-slider-section", text: /Alle Veranstaltungen in Stuttgart/ do
      assert_select ".home-slider-card-name", text: reservix_event.artist_name
      assert_select ".home-slider-card-name", text: late_reservix_event.artist_name
      assert_select ".home-slider-card-name", text: eventim_event.artist_name, count: 0
    end
  end

  test "index limits the all events slider to 100 reservix events" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)
    included_event_names = []
    excluded_event_name = nil

    101.times do |index|
      artist_name = "Reservix Limited Artist #{index}"
      included_event_names << artist_name if index < 100
      excluded_event_name = artist_name if index == 100

      Event.create!(
        slug: "reservix-home-slider-limited-#{index}",
        source_fingerprint: "test::homepage::reservix::limited::#{index}",
        title: "Reservix Homepage Limited #{index}",
        artist_name: artist_name,
        start_at: future_start + index.minutes,
        venue: "Venue #{index}",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        primary_source: "reservix",
        source_snapshot: {}
      )
    end

    get events_url(filter: "all")

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    slider_section = document.css("section.home-slider-section").find do |section|
      section.at_css("h2")&.text == "Alle Veranstaltungen in Stuttgart"
    end

    assert slider_section.present?, "expected all events slider section to be rendered"

    names = slider_section.css(".home-slider-card-name").map(&:text)

    assert_equal 100, names.size
    assert_includes names, included_event_names.first
    assert_includes names, included_event_names.last
    assert_not_includes names, excluded_event_name
  end

  test "index does not limit highlights fallback when no sks events exist for the selected date" do
    selected_date = 20.days.from_now.to_date

    12.times do |index|
      Event.create!(
        slug: "highlights-fallback-event-#{index}",
        source_fingerprint: "test::homepage::highlights::fallback::#{index}",
        title: "Highlights Fallback Event #{index}",
        artist_name: "Highlights Fallback Artist #{index}",
        start_at: selected_date.in_time_zone.change(hour: 10 + index, min: 0, sec: 0),
        venue: "Fallback Venue #{index}",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        promoter_id: "99999",
        source_snapshot: {}
      )
    end

    final_event = Event.create!(
      slug: "highlights-fallback-event-final",
      source_fingerprint: "test::homepage::highlights::fallback::final",
      title: "Highlights Fallback Final Event",
      artist_name: "Highlights Fallback Final Artist",
      start_at: selected_date.in_time_zone.change(hour: 23, min: 0, sec: 0),
      venue: "Fallback Venue Final",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "99999",
      source_snapshot: {}
    )

    get events_url(filter: "all", event_date: selected_date.iso8601)

    assert_response :success
    assert_select "section.home-featured-section", text: /Highlights/ do
      assert_select ".event-card-copy h2", text: final_event.artist_name
    end
  end

  test "index shows only today's non-reservix events in tagestipp" do
    today_start = Time.zone.now.change(hour: 20, min: 0, sec: 0)

    sks_today_event = Event.create!(
      slug: "tagestipp-sks-today-event",
      source_fingerprint: "test::homepage::tagestipp::sks",
      title: "SKS Spotlight Event",
      artist_name: "SKS Today Artist",
      start_at: today_start + 3.hours,
      venue: "Schleyer-Halle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      source_snapshot: {}
    )

    today_event = Event.create!(
      slug: "tagestipp-today-event",
      source_fingerprint: "test::homepage::tagestipp::today",
      title: "Today Spotlight Event",
      artist_name: "Today Slider Artist",
      start_at: today_start,
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )

    reservix_today_event = Event.create!(
      slug: "tagestipp-reservix-today-event",
      source_fingerprint: "test::homepage::tagestipp::reservix",
      title: "Reservix Spotlight Event",
      artist_name: "Reservix Today Artist",
      start_at: today_start + 1.hour,
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      source_snapshot: {}
    )

    tomorrow_event = Event.create!(
      slug: "tagestipp-tomorrow-event",
      source_fingerprint: "test::homepage::tagestipp::tomorrow",
      title: "Tomorrow Spotlight Event",
      artist_name: "Tomorrow Slider Artist",
      start_at: today_start + 1.day,
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "easyticket",
      source_snapshot: {}
    )

    10.times do |index|
      Event.create!(
        slug: "tagestipp-filler-event-#{index}",
        source_fingerprint: "test::homepage::tagestipp::filler::#{index}",
        title: "Tagestipp Filler Event #{index}",
        artist_name: "Tagestipp Filler Artist #{index}",
        start_at: today_start - (index + 1).minutes,
        venue: "Club #{index}",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        primary_source: index.even? ? "eventim" : "easyticket",
        source_snapshot: {}
      )
    end

    late_today_event = Event.create!(
      slug: "tagestipp-late-today-event",
      source_fingerprint: "test::homepage::tagestipp::late",
      title: "Late Spotlight Event",
      artist_name: "Late Today Artist",
      start_at: today_start + 2.hours,
      venue: "Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    tagestipp_section = document.css("section.home-slider-section").find do |section|
      section.at_css("h2")&.text == "Tagestipp"
    end

    assert tagestipp_section.present?, "expected Tagestipp section to be rendered"

    names = tagestipp_section.css(".home-slider-card-name").map(&:text)

    assert_equal sks_today_event.artist_name, names.first
    assert_includes names, today_event.artist_name
    assert_includes names, late_today_event.artist_name
    assert_not_includes names, reservix_today_event.artist_name
    assert_not_includes names, tomorrow_event.artist_name
  end

  test "index can be filtered to SKS events" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)

    sks_easy_event = Event.create!(
      slug: "sks-easy-event",
      source_fingerprint: "test::sks::easy",
      title: "SKS Easy Event",
      artist_name: "SKS Easy Artist",
      start_at: future_start,
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "382",
      source_snapshot: {}
    )

    sks_eventim_event = Event.create!(
      slug: "sks-eventim-event",
      source_fingerprint: "test::sks::eventim",
      title: "SKS Eventim Event",
      artist_name: "SKS Eventim Artist",
      start_at: future_start + 1.hour,
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "10135",
      source_snapshot: {}
    )

    sks_easyticket_promoter_event = Event.create!(
      slug: "sks-easyticket-promoter-event",
      source_fingerprint: "test::sks::easyticket::promoter",
      title: "SKS Easyticket Promoter Event",
      artist_name: "SKS Easyticket Promoter Artist",
      start_at: future_start + 90.minutes,
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "382",
      source_snapshot: {}
    )

    non_sks_event = Event.create!(
      slug: "non-sks-event",
      source_fingerprint: "test::non::sks",
      title: "Non SKS Event",
      artist_name: "Other Artist",
      start_at: future_start + 2.hours,
      venue: "Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "99999",
      source_snapshot: {}
    )

    get events_url(filter: "sks")

    assert_response :success
    assert_includes response.body, sks_easy_event.artist_name
    assert_includes response.body, sks_eventim_event.artist_name
    assert_includes response.body, sks_easyticket_promoter_event.artist_name
    assert_select ".home-featured-track", text: /#{Regexp.escape(sks_easy_event.artist_name)}/
    assert_select ".home-featured-track", text: /#{Regexp.escape(sks_eventim_event.artist_name)}/
    assert_select ".home-featured-track", text: /#{Regexp.escape(sks_easyticket_promoter_event.artist_name)}/
    assert_select ".home-featured-track", text: /#{Regexp.escape(non_sks_event.artist_name)}/, count: 0
  end

  test "index can be filtered to a specific day" do
    selected_date = 12.days.from_now.to_date
    selected_start = selected_date.to_time.in_time_zone.change(hour: 20, min: 0, sec: 0)

    matching_event = Event.create!(
      slug: "day-filter-match",
      source_fingerprint: "test::day::match",
      title: "Day Filter Match",
      artist_name: "Day Match Artist",
      start_at: selected_start,
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "10135",
      source_snapshot: {}
    )

    other_day_event = Event.create!(
      slug: "day-filter-other",
      source_fingerprint: "test::day::other",
      title: "Day Filter Other",
      artist_name: "Other Day Artist",
      start_at: selected_start + 1.day,
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "10135",
      source_snapshot: {}
    )

    get events_url(filter: "sks", event_date: selected_date.iso8601)

    assert_response :success
    assert_includes response.body, matching_event.artist_name
    assert_not_includes response.body, other_day_event.artist_name
    assert_includes response.body, "event_date=#{selected_date.iso8601}"
  end

  test "index renders only the search filter in the public filter row" do
    get events_url(filter: "all", view: "list")

    assert_response :success
    assert_select ".public-filter-row-main .public-search-filter", count: 1
    assert_select ".public-filter-row-main .public-view-toggle", count: 0
    assert_select ".public-filter-row-main input[name='view']", count: 0
  end

  test "index redirects to detail page when search has a single result" do
    get events_url(filter: "all", q: @published_event.artist_name)

    assert_redirected_to event_url(@published_event.slug)
  end

  test "index search ignores the default sks filter for a single result" do
    non_sks_event = Event.create!(
      slug: "search-single-non-sks",
      source_fingerprint: "test::search::single::non-sks",
      title: "Search Single Non SKS",
      artist_name: "Search Single Non SKS Artist",
      start_at: 17.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Theaterhaus",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "99999",
      primary_source: "reservix",
      source_snapshot: {}
    )

    get events_url(q: non_sks_event.artist_name)

    assert_redirected_to event_url(non_sks_event.slug)
  end

  test "index renders flat search results and keeps homepage sliders for multiple matches" do
    first_event = Event.create!(
      slug: "search-multi-first",
      source_fingerprint: "test::search::multi::first",
      title: "Search Cluster Night One",
      artist_name: "Search Cluster",
      start_at: 13.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    second_event = Event.create!(
      slug: "search-multi-second",
      source_fingerprint: "test::search::multi::second",
      title: "Search Cluster Night Two",
      artist_name: "Search Cluster",
      start_at: 14.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    reservix_slider_event = Event.create!(
      slug: "search-page-reservix-slider",
      source_fingerprint: "test::search::reservix::slider",
      title: "Reservix Slider Night",
      artist_name: "Reservix Slider Artist",
      start_at: 15.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Theaterhaus",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      source_snapshot: {}
    )

    tagestipp_event = Event.create!(
      slug: "search-page-tagestipp",
      source_fingerprint: "test::search::tagestipp",
      title: "Tagestipp Search Day Event",
      artist_name: "Tagestipp Search Artist",
      start_at: Time.zone.now.change(hour: 21, min: 0, sec: 0),
      venue: "Club Cann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )

    get events_url(filter: "all", q: "Search Cluster")

    assert_response :success
    assert_select "#event-grid .event-card-grid-1-1", count: 2
    assert_includes response.body, first_event.title
    assert_includes response.body, second_event.title
    assert_includes response.body, "Alle Veranstaltungen in Stuttgart"
    assert_includes response.body, reservix_slider_event.artist_name
    assert_includes response.body, "Tagestipp"
    assert_includes response.body, tagestipp_event.artist_name
    assert_includes response.body, @published_event.artist_name
  end

  test "highlight list rows prefer easyticket offer" do
    event = Event.create!(
      slug: "list-view-ticket-priority",
      source_fingerprint: "test::public::list::ticket-priority",
      title: "List Ticket Priority",
      artist_name: "List Ticket Artist",
      start_at: 2.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      source_snapshot: {}
    )

    event.event_offers.create!(
      source: "eventim",
      source_event_id: "eventim-123",
      ticket_url: "https://eventim.example/tickets",
      sold_out: false,
      priority_rank: 1,
      metadata: {}
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-123",
      ticket_url: "https://easyticket.example/tickets",
      sold_out: false,
      priority_rank: 50,
      metadata: {}
    )

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "https://easyticket.example/tickets"
    assert_not_includes response.body, "https://eventim.example/tickets"
  end

  test "show prefers easyticket offer for primary ticket cta" do
    event = Event.create!(
      slug: "show-ticket-priority",
      source_fingerprint: "test::public::show::ticket-priority",
      title: "Show Ticket Priority",
      artist_name: "Show Ticket Artist",
      start_at: 15.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event.event_offers.create!(
      source: "eventim",
      source_event_id: "eventim-show-123",
      ticket_url: "https://eventim.example/show-tickets",
      sold_out: false,
      priority_rank: 1,
      metadata: {}
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-show-123",
      ticket_url: "https://easyticket.example/show-tickets",
      sold_out: false,
      priority_rank: 50,
      metadata: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "https://easyticket.example/show-tickets"
    assert_not_includes response.body, "https://eventim.example/show-tickets"
  end

  test "show renders published event by slug" do
    extra_genre = genres(:jazz)
    @published_event.genres << genres(:pop)
    @published_event.genres << extra_genre

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Events"
    assert_includes response.body, "Published Artist"
    assert_match(/Beginn:\s*\d{2}:\d{2}\s*Uhr/, response.body)
    assert_match(/Einlass:\s*\d{2}:\d{2}\s*Uhr/, response.body)
    assert_includes response.body, "Preis: 45 EUR"
    assert_select ".event-detail-genre", text: "Genre: Jazz · Pop · Rock"
  end

  test "show gates youtube embeds behind consent placeholder" do
    @published_event.update!(youtube_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, "YouTube laden"
    assert_includes response.body, "Datenschutzeinstellungen"
    assert_select "[data-consent-media-target='frame'] iframe", count: 0
    assert_select "template iframe[src=?]", "https://www.youtube.com/embed/dQw4w9WgXcQ"
  end

  test "show does not render dangling comma when city is blank" do
    @published_event.update!(city: nil)

    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, @published_event.venue
    assert_not_includes response.body, "#{@published_event.venue}, </span>"
    assert_no_match(/#{Regexp.escape(@published_event.venue)}\s*,\s*<\/span>/, response.body)
  end

  test "show renders einlass when present" do
    event = Event.create!(
      slug: "published-event-with-einlass",
      source_fingerprint: "test::public::published::einlass",
      title: "Published Event With Einlass",
      artist_name: "Published Artist With Einlass",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      doors_at: 10.days.from_now.change(hour: 18, min: 30, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_match(/Einlass:\s*\d{2}:\d{2}\s*Uhr/, response.body)
  end

  test "show renders redaktionsnotiz section when editor notes are present" do
    event = Event.create!(
      slug: "published-event-with-editor-notes",
      source_fingerprint: "test::public::published::editor-notes",
      title: "Published Event With Editor Notes",
      artist_name: "Published Artist With Notes",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      event_info: "Öffentliche Beschreibung",
      editor_notes: "Interner Hinweis\nZweite Zeile",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Redaktionsnotiz"
    assert_includes response.body, "Interner Hinweis"
  end

  test "show hides organizer notes unless explicitly enabled" do
    event = Event.create!(
      slug: "published-event-with-hidden-organizer-notes",
      source_fingerprint: "test::public::published::hidden-organizer-notes",
      title: "Published Event With Hidden Organizer Notes",
      artist_name: "Published Artist Hidden Notes",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      event_info: "Öffentliche Beschreibung",
      organizer_notes: "Interne Veranstalterhinweise",
      show_organizer_notes: false,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_not_includes response.body, "Veranstalterhinweise"
    assert_not_includes response.body, "Interne Veranstalterhinweise"
  end

  test "show renders organizer notes when explicitly enabled" do
    event = Event.create!(
      slug: "published-event-with-visible-organizer-notes",
      source_fingerprint: "test::public::published::visible-organizer-notes",
      title: "Published Event With Visible Organizer Notes",
      artist_name: "Published Artist Visible Notes",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      event_info: "Öffentliche Beschreibung",
      organizer_notes: "Sichtbare Veranstalterhinweise",
      show_organizer_notes: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Veranstalterhinweise"
    assert_includes response.body, "Sichtbare Veranstalterhinweise"
  end

  test "show renders organizer notes for sks events by default" do
    event = Event.create!(
      slug: "published-sks-event-with-default-organizer-notes",
      source_fingerprint: "test::public::published::sks-default-organizer-notes",
      title: "Published SKS Event",
      artist_name: "Published SKS Artist",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      event_info: "Öffentliche Beschreibung",
      organizer_notes: nil,
      show_organizer_notes: false,
      promoter_id: Event::SKS_PROMOTER_IDS.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Veranstalterhinweise"
    assert_includes response.body, "Wir danken für Ihr Verständnis!"
  end

  test "show includes edit link for authenticated users" do
    sign_in_as(@user)

    get event_url(@published_event.slug)

    assert_response :success
    expected_link = backend_events_path(status: @published_event.status, event_id: @published_event.id).gsub("&", "&amp;")
    assert_select ".event-detail-badges-row .status-badge", text: "easyticket"
    assert_includes response.body, expected_link
    assert_select ".event-detail-topbar-actions .button", text: "Open"
    assert_no_match(/Bearbeiten/, response.body)
  end

  test "show returns not found for unpublished events" do
    get event_url(events(:needs_review_one).slug)

    assert_response :not_found
    assert_includes response.body, "Dieses Event ist nicht mehr da."
    assert_includes response.body, "Zur Startseite"
  end

  test "show returns not found for ready_for_publish events for guests" do
    event = Event.create!(
      slug: "ready-for-publish-public-detail",
      source_fingerprint: "test::public::ready-for-publish::detail",
      title: "Ready For Publish Public Detail",
      artist_name: "Ready Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "ready_for_publish",
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :not_found
    assert_includes response.body, "Dieses Event ist nicht mehr da."
  end

  test "show renders unpublished events for authenticated users with status badge" do
    sign_in_as(@user)

    event = events(:needs_review_one)
    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Draft"
  end

  test "show renders ready_for_publish events for authenticated users with status badge" do
    sign_in_as(@user)

    event = Event.create!(
      slug: "ready-for-publish-auth-detail",
      source_fingerprint: "test::public::ready-for-publish::auth-detail",
      title: "Ready For Publish Auth Detail",
      artist_name: "Ready Auth Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "ready_for_publish",
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Unpublished"
  end

  test "show renders rejected events for authenticated users with abgelehnt badge" do
    sign_in_as(@user)

    rejected_event = Event.create!(
      slug: "rejected-public-detail",
      source_fingerprint: "test::public::rejected::detail",
      title: "Rejected Public Detail",
      artist_name: "Rejected Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "rejected",
      source_snapshot: {}
    )

    get event_url(rejected_event.slug)

    assert_response :success
    assert_includes response.body, "Rejected"
  end

  test "show renders published past events by slug" do
    get event_url(@past_published_event.slug)

    assert_response :success
    assert_includes response.body, "Past Artist"
  end

  test "show renders past events for authenticated users with vergangen badge" do
    sign_in_as(@user)

    get event_url(@past_published_event.slug)

    assert_response :success
    assert_includes response.body, "Vergangen"
  end

  test "index shows status overlay for authenticated users" do
    sign_in_as(@user)
    event = @published_event

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "event-card-status-select"
    assert_includes response.body, status_event_path(event.slug)
    assert_includes response.body, "data-controller=\"public-card-status\""
    assert_includes response.body, "change-&gt;public-card-status#change"
    assert_includes response.body, "/backend/events?event_id=#{event.id}&amp;status=#{event.status}"
  end

  test "status update requires authentication" do
    patch status_event_url(@published_event.slug), params: { status: "needs_review" }

    assert_redirected_to new_session_url
  end

  test "authenticated user can update event status from public cards" do
    sign_in_as(@user)

    patch status_event_url(@published_event.slug), params: { status: "needs_review", page: "1", filter: "all", event_date: "2026-06-01" }

    assert_redirected_to events_url(page: "1", event_date: "2026-06-01")
    assert_equal "needs_review", @published_event.reload.status
    assert_nil @published_event.published_at
    assert_nil @published_event.published_by_id
  end

  test "turbo status update removes event card when event becomes unpublished" do
    sign_in_as(@user)

    patch status_event_url(@published_event.slug),
      params: { status: "needs_review", card_slot: "grid_default" },
      as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "action=\"remove\""
    assert_includes response.body, "target=\"card_event_#{@published_event.id}\""
  end

  test "show prefers editorial hero and renders slider images with sub text" do
    hero_image = create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      sub_text: "Foto Max Mustermann",
      grid_variant: EventImage::GRID_VARIANT_1X1
    )
    slider_image = create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_SLIDER,
      alt_text: "Slider Alt",
      sub_text: "Slider Subline"
    )

    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, @published_event.artist_name
    assert_includes response.body, "© Foto Max Mustermann"
    assert_includes response.body, "Slider Subline"
    assert_includes response.body, rails_storage_proxy_path(hero_image.file, only_path: true)
    assert_includes response.body, rails_storage_proxy_path(slider_image.file, only_path: true)
    refute_includes response.body, "/rails/active_storage/blobs/redirect/"
  end

  test "show falls back to import image when no event image exists" do
    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, "https://example.com/published.jpg"
  end

  test "index uses event image crop variant for grid tile size" do
    image = create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      grid_variant: EventImage::GRID_VARIANT_2X2,
      alt_text: "Grid 2x2 Alt"
    )

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "event-card-grid-2-2"
    assert_includes response.body, "Grid 2x2 Alt"
    assert_includes response.body, rails_storage_proxy_path(image.file, only_path: true)
    refute_includes response.body, "/rails/active_storage/blobs/redirect/"
  end

  test "index uses event image crop variant outside the old pattern slot" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      grid_variant: EventImage::GRID_VARIANT_1X2,
      alt_text: "Grid 1x2 Alt"
    )

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "event-card-grid-1-2"
    assert_includes response.body, "Grid 1x2 Alt"
  end

  test "index defaults to 1x1 when event image has no crop variant" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "Eventbild Default Alt"
    )

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "event-card-grid-1-1"
    assert_includes response.body, "Eventbild Default Alt"
  end

  private

  def create_event_image(event:, purpose:, grid_variant: nil, alt_text: nil, sub_text: nil)
    image = event.event_images.new(
      purpose: purpose,
      grid_variant: grid_variant,
      alt_text: alt_text,
      sub_text: sub_text
    )
    binary = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
    image.file.attach(
      io: StringIO.new(binary),
      filename: "test_image.png",
      content_type: "image/png"
    )
    image.save!
    image
  end
end
