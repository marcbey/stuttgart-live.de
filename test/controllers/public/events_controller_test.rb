require "test_helper"

class Public::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.where(key: AppSetting::SKS_ORGANIZER_NOTES_KEY).delete_all
    AppSetting.where(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY).delete_all
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [ "10135", "10136", "382" ])
    AppSetting.create!(key: AppSetting::SKS_ORGANIZER_NOTES_KEY, value: "Konfigurierter SKS Hinweis\nWir danken für Ihr Verständnis!")
    AppSetting.reset_cache!
    @published_event = events(:published_one)
    @past_published_event = events(:published_past_one)
    @user = users(:one)
  end

  teardown do
    AppSetting.reset_cache!
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.where(key: AppSetting::SKS_ORGANIZER_NOTES_KEY).delete_all
    AppSetting.where(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY).delete_all
  end

  test "index is publicly accessible" do
    get events_url(filter: "all")

    assert_response :success
    assert_not_includes response.body, "fonts.googleapis.com"
    assert_not_includes response.body, "fonts.gstatic.com"
    assert_select "script[type='module'][src*='/assets/public']", count: 1
    assert_select "script[type='module'][src*='/assets/backend']", count: 0
    assert_select "script[type='module'][src*='/assets/application']", count: 0
    assert_select "link[rel='preload'][as='font'][href*='archivo-narrow-400']", count: 1
    assert_select "link[rel='preload'][as='font'][href*='bebas-neue-400']", count: 1
    assert_select "style[data-local-font-faces]", count: 1
    assert_includes response.body, ActionController::Base.helpers.asset_path("archivo-narrow-700.woff2")
    assert_includes response.body, ActionController::Base.helpers.asset_path("oswald-500.woff2")
    assert_includes response.body, ActionController::Base.helpers.asset_path("oswald-700.woff2")
    assert_includes response.body, ActionController::Base.helpers.asset_path("bebas-neue-400.woff2")
    assert_select ".lane-header.lane-header--highlights", count: 1
    assert_select ".app-nav-links .app-nav-link-active", text: "Events"
    assert_select ".app-nav-hotline", text: /Dein Ticketportal für Stuttgart und Region -\s*0711 550 660 77/
    assert_select ".app-nav-hotline-contact .app-nav-link", text: "Kontakt"
    assert_includes response.body, "Published Artist"
    assert_not_includes response.body, "Past Artist"
    assert_not_includes response.body, "Review Artist"
    assert_not_includes response.body, "event-card-status-select"
    assert_select ".event-card-genre", count: 0
    assert_select ".genre-lane-section", count: 0
  end

  test "index renders configured homepage genre lanes in priority order" do
    snapshot, rock_group, pop_group = create_homepage_genre_snapshot
    AppSetting.create!(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY, value: [ pop_group.slug, rock_group.slug ])
    AppSetting.reset_cache!

    highlighted_event = Event.create!(
      slug: "genre-lane-highlighted",
      source_fingerprint: "test::public::genre-lane::highlighted",
      title: "Genre Lane Highlighted",
      artist_name: "Highlighted Lane Artist",
      start_at: 8.days.from_now.change(hour: 22, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      highlighted: true,
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )
    sks_event = Event.create!(
      slug: "genre-lane-sks",
      source_fingerprint: "test::public::genre-lane::sks",
      title: "Genre Lane SKS",
      artist_name: "SKS Lane Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      primary_source: "easyticket",
      source_snapshot: {}
    )
    regular_event = Event.create!(
      slug: "genre-lane-regular",
      source_fingerprint: "test::public::genre-lane::regular",
      title: "Genre Lane Regular",
      artist_name: "Regular Lane Artist",
      start_at: 8.days.from_now.change(hour: 18, min: 0, sec: 0),
      venue: "Club Zentral",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      source_snapshot: {}
    )
    pop_event = Event.create!(
      slug: "genre-lane-pop",
      source_fingerprint: "test::public::genre-lane::pop",
      title: "Genre Lane Pop",
      artist_name: "Pop Lane Artist",
      start_at: 9.days.from_now.change(hour: 19, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )
    unpublished_event = Event.create!(
      slug: "genre-lane-unpublished",
      source_fingerprint: "test::public::genre-lane::unpublished",
      title: "Genre Lane Unpublished",
      artist_name: "Unpublished Lane Artist",
      start_at: 8.days.from_now.change(hour: 21, min: 0, sec: 0),
      venue: "Club Zwölfzehn",
      city: "Stuttgart",
      status: "needs_review",
      source_snapshot: {}
    )
    past_event = Event.create!(
      slug: "genre-lane-past",
      source_fingerprint: "test::public::genre-lane::past",
      title: "Genre Lane Past",
      artist_name: "Past Lane Artist",
      start_at: 3.days.ago.change(hour: 20, min: 0, sec: 0),
      venue: "Club Cann",
      city: "Stuttgart",
      status: "published",
      published_at: 5.days.ago,
      source_snapshot: {}
    )

    build_homepage_genre_enrichment(event: highlighted_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: sks_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: regular_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: pop_event, genres: [ "Pop" ])
    build_homepage_genre_enrichment(event: unpublished_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: past_event, genres: [ "Rock" ])

    get events_url(filter: "all")

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    shell_children = document.css("section.public-shell > *").to_a
    genre_sections = document.css("section.genre-lane-section")
    pop_section = genre_sections.find { |section| section.at_css("h2")&.text == pop_group.name }
    rock_section = genre_sections.find { |section| section.at_css("h2")&.text == rock_group.name }
    highlights_index = shell_children.index { |node| node.name == "section" && node["class"].to_s.include?("home-featured-section") }
    saved_lane_slot_index = shell_children.index { |node| node["id"] == "saved-events-lane-slot" }
    first_genre_index = shell_children.index { |node| node.name == "section" && node["class"].to_s.include?("genre-lane-section") }
    all_events_index = shell_children.index do |node|
      node.name == "section" && node["class"].to_s.include?("genre-lane-section") && node.at_css("h2")&.text == "alles aus stuttgart"
    end
    last_homepage_lane_index = shell_children.rindex do |node|
      next true if node.name == "section" && node["class"].to_s.include?("genre-lane-section")
      node.name == "section" && node["class"].to_s.include?("home-featured-section")
    end

    assert_equal snapshot.id, LlmGenreGrouping::Lookup.selected_snapshot.id
    assert pop_section.present?, "expected configured pop lane to be rendered"
    assert rock_section.present?, "expected configured rock lane to be rendered"
    assert document.at_css(".lane-header.lane-header--genre").present?, "expected standard genre header variant"
    assert_equal highlights_index + 1, first_genre_index
    assert_operator all_events_index, :>, first_genre_index
    assert_equal last_homepage_lane_index + 1, saved_lane_slot_index

    pop_names = pop_section.css(".genre-lane-card-name").map(&:text)
    rock_names = rock_section.css(".genre-lane-card-name").map(&:text)

    assert_equal [ pop_event.artist_name ], pop_names
    assert_equal [ regular_event.artist_name, sks_event.artist_name, highlighted_event.artist_name ], rock_names
    assert_not_includes rock_names, unpublished_event.artist_name
    assert_not_includes rock_names, past_event.artist_name
  end

  test "index does not render homepage genre lanes without selected snapshot" do
    AppSetting.reset_cache!

    get events_url(filter: "all")

    assert_response :success
    assert_select ".genre-lane-section", count: 0
  end

  test "index renders a pop lane on the homepage even when it is not selected in the lane configuration" do
    snapshot, rock_group, pop_group = create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])

    rock_event = Event.create!(
      slug: "genre-lane-rock-fallback",
      source_fingerprint: "test::public::genre-lane::rock-fallback",
      title: "Genre Lane Rock Fallback",
      artist_name: "Rock Lane Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    pop_event = Event.create!(
      slug: "genre-lane-pop-fallback",
      source_fingerprint: "test::public::genre-lane::pop-fallback",
      title: "Genre Lane Pop Fallback",
      artist_name: "Pop Lane Fallback Artist",
      start_at: 9.days.from_now.change(hour: 19, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    build_homepage_genre_enrichment(event: rock_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: pop_event, genres: [ "Pop" ])

    get events_url(filter: "all")

    assert_response :success
    assert_equal snapshot.id, LlmGenreGrouping::Lookup.selected_snapshot.id

    sections = Nokogiri::HTML.parse(response.body).css("section.genre-lane-section")
    rendered_titles = sections.filter_map { |section| section.at_css("h2")&.text }

    assert_includes rendered_titles, rock_group.name
    assert_includes rendered_titles, pop_group.name
    assert_equal 1, rendered_titles.count { |title| title == pop_group.name }
  end

  test "index orders the explicit pop lane chronologically without sks or highlight promotion" do
    snapshot, _, pop_group = create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])

    earlier_pop_event = Event.create!(
      slug: "genre-lane-pop-chronological-earlier",
      source_fingerprint: "test::public::genre-lane::pop-chronological::earlier",
      title: "Genre Lane Pop Chronological Earlier",
      artist_name: "Pop Earlier Artist",
      start_at: 9.days.from_now.change(hour: 18, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    sks_pop_event = Event.create!(
      slug: "genre-lane-pop-chronological-sks",
      source_fingerprint: "test::public::genre-lane::pop-chronological::sks",
      title: "Genre Lane Pop Chronological SKS",
      artist_name: "Pop SKS Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Schleyer-Halle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    highlighted_pop_event = Event.create!(
      slug: "genre-lane-pop-chronological-highlighted",
      source_fingerprint: "test::public::genre-lane::pop-chronological::highlighted",
      title: "Genre Lane Pop Chronological Highlighted",
      artist_name: "Pop Highlighted Artist",
      start_at: 9.days.from_now.change(hour: 22, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      highlighted: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    build_homepage_genre_enrichment(event: earlier_pop_event, genres: [ "Pop" ])
    build_homepage_genre_enrichment(event: sks_pop_event, genres: [ "Pop" ])
    build_homepage_genre_enrichment(event: highlighted_pop_event, genres: [ "Pop" ])

    get events_url(filter: "all")

    assert_response :success
    assert_equal snapshot.id, LlmGenreGrouping::Lookup.selected_snapshot.id

    pop_section = Nokogiri::HTML.parse(response.body).css("section.genre-lane-section").find do |section|
      section.at_css("h2")&.text == pop_group.name
    end

    assert pop_section.present?, "expected pop lane to be rendered"

    assert_equal [
      earlier_pop_event.artist_name,
      sks_pop_event.artist_name,
      highlighted_pop_event.artist_name
    ], pop_section.css(".genre-lane-card-name").map(&:text)
  end

  test "index renders a pop lane on the homepage without any selected snapshot" do
    AppSetting.where(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY).delete_all
    AppSetting.reset_cache!

    pop_event = Event.create!(
      slug: "genre-lane-pop-no-snapshot",
      source_fingerprint: "test::public::genre-lane::pop-no-snapshot",
      title: "Genre Lane Pop No Snapshot",
      artist_name: "Pop Lane Without Snapshot",
      start_at: 9.days.from_now.change(hour: 19, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    build_homepage_genre_enrichment(event: pop_event, genres: [ "Pop" ])

    get events_url(filter: "all")

    assert_response :success
    assert_select ".genre-lane-section h2", text: "Pop"
    assert_select ".genre-lane-card-name", text: pop_event.artist_name
  end

  test "homepage lane header titles link to their landing pages when available" do
    _, rock_group, = create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])

    Event.create!(
      slug: "lane-link-highlight",
      source_fingerprint: "test::public::lane-link::highlight",
      title: "Lane Link Highlight",
      artist_name: "Lane Link Highlight Artist",
      start_at: 7.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )

    Event.create!(
      slug: "lane-link-rock",
      source_fingerprint: "test::public::genre-lane::link::rock",
      title: "Lane Link Rock",
      artist_name: "Lane Link Rock Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Club Zentral",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    ).tap do |event|
      build_homepage_genre_enrichment(event: event, genres: [ "Rock" ])
    end

    Event.create!(
      slug: "lane-link-reservix",
      source_fingerprint: "test::public::lane-link::reservix",
      title: "Lane Link Reservix",
      artist_name: "Lane Link Reservix Artist",
      start_at: 8.days.from_now.change(hour: 18, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      source_snapshot: {}
    )

    Event.create!(
      slug: "lane-link-tagestipp",
      source_fingerprint: "test::public::lane-link::tagestipp",
      title: "Lane Link Tagestipp",
      artist_name: "Lane Link Tagestipp Artist",
      start_at: Time.zone.today.change(hour: 19, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )

    get events_url

    assert_response :success
    assert_select ".lane-header--highlights .lane-header-title-link[href='/highlights']", count: 1
    assert_select ".lane-header--editorial .lane-header-title-link[href='/alles-aus-stuttgart']", count: 1
    assert_select ".lane-header--tagestipp .lane-header-title-link[href='/tagestipp']", count: 1
    assert_select ".lane-header--genre .lane-header-title-link[href='/#{rock_group.slug}']", text: rock_group.name, count: 1
  end

  test "homepage lane title stays plain text when the genre lane slug collides with a static page" do
    create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])
    StaticPage.create!(
      slug: "rock-alternative",
      title: "Rock Alternative Landing",
      intro: "Intro",
      body: "<div>Eigene Seite</div>"
    )

    Event.create!(
      slug: "lane-collision-rock",
      source_fingerprint: "test::public::genre-lane::collision::rock",
      title: "Lane Collision Rock",
      artist_name: "Lane Collision Rock Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Club Zentral",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    ).tap do |event|
      build_homepage_genre_enrichment(event: event, genres: [ "Rock" ])
    end

    get events_url

    assert_response :success
    assert_select ".lane-header--genre .lane-header-title", text: "Rock & Alternative", count: 1
    assert_select ".lane-header--genre .lane-header-title-link[href='/rock-alternative']", count: 0
  end

  test "fixed lane pages render their full matching event list" do
    reservix_event = Event.create!(
      slug: "lane-page-all-stuttgart",
      source_fingerprint: "test::public::lane-page::all-stuttgart",
      title: "Lane Page All Stuttgart",
      artist_name: "Lane Page All Stuttgart Artist",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      source_snapshot: {}
    )
    today_event = Event.create!(
      slug: "lane-page-tagestipp",
      source_fingerprint: "test::public::lane-page::tagestipp",
      title: "Lane Page Tagestipp",
      artist_name: "Lane Page Tagestipp Artist",
      start_at: Time.zone.today.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      source_snapshot: {}
    )

    get "/alles-aus-stuttgart"

    assert_response :success
    assert_select "section.lane-page-section.search-results-section", count: 1
    assert_select ".lane-header.lane-header--editorial .lane-header-title", text: "alles aus stuttgart"
    assert_select ".lane-page-section .lane-header-nav .slider-view-toggle", count: 1
    assert_select "#lane-event-grid", count: 1
    assert_select "#lane-event-grid article.genre-lane-card", minimum: 1
    assert_select "#lane-event-grid .genre-lane-card-name", text: reservix_event.artist_name

    get "/tagestipp"

    assert_response :success
    assert_select ".lane-header.lane-header--tagestipp .lane-header-title", text: "Tagestipp"
    assert_select "#lane-event-grid .genre-lane-card-name", text: today_event.artist_name
  end

  test "genre lane page resolves by snapshot group slug even when it is not on the homepage" do
    _, _, pop_group = create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])

    18.times do |index|
      Event.create!(
        slug: "lane-page-pop-#{index}",
        source_fingerprint: "test::public::lane-page::pop::#{index}",
        title: "Lane Page Pop #{index}",
        artist_name: "Lane Page Pop Artist #{index}",
        start_at: (index + 2).days.from_now.change(hour: 18, min: 0, sec: 0),
        venue: "Porsche-Arena",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        primary_source: "eventim",
        source_snapshot: {}
      ).tap do |event|
        build_homepage_genre_enrichment(event: event, genres: [ "Pop" ])
      end
    end

    get "/#{pop_group.slug}"

    assert_response :success
    assert_select ".lane-header.lane-header--genre .lane-header-title", text: pop_group.name
    assert_select "#lane-event-grid article.genre-lane-card", minimum: 18
    assert_select "#lane-event-grid .genre-lane-card-name", text: "Lane Page Pop Artist 17"
  end

  test "genre lane route falls through to a static page on slug collision" do
    create_homepage_genre_snapshot
    StaticPage.create!(
      slug: "rock-alternative",
      title: "Eigene Rockseite",
      intro: "Intro",
      body: "<div>Statische Inhalte</div>"
    )

    get "/rock-alternative"

    assert_response :success
    assert_select "h1", text: "Eigene Rockseite"
    assert_select ".lane-header.lane-header--genre", count: 0
  end

  test "unknown genre lane slug returns not found" do
    create_homepage_genre_snapshot

    get "/definitiv-unbekannte-lane"

    assert_response :not_found
  end

  test "index does not mark a singleton series as event series in public lanes" do
    create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])

    series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
    visible_event = Event.create!(
      slug: "singleton-series-visible",
      source_fingerprint: "test::public::singleton-series::visible",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )
    hidden_event = Event.create!(
      slug: "singleton-series-hidden",
      source_fingerprint: "test::public::singleton-series::hidden",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    build_homepage_genre_enrichment(event: visible_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: hidden_event, genres: [ "Rock" ])

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, visible_event.artist_name
    assert_select ".event-series-badge", count: 0
  end

  test "index keeps the event series badge on deduplicated teaser lane representatives" do
    create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])

    series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
    earlier_event = Event.create!(
      slug: "dedup-series-earlier-visible",
      source_fingerprint: "test::public::dedup-series::earlier",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 8.days.from_now.change(hour: 18, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )
    later_event = Event.create!(
      slug: "dedup-series-later-visible",
      source_fingerprint: "test::public::dedup-series::later",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    build_homepage_genre_enrichment(event: earlier_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: later_event, genres: [ "Rock" ])

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, earlier_event.artist_name
    assert_select ".event-series-badge", minimum: 1
  end

  test "index does not render event series badges in list view rows" do
    create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])

    series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
    first_event = Event.create!(
      slug: "list-view-series-first",
      source_fingerprint: "test::public::list-view-series::first",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 8.days.from_now.change(hour: 18, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )
    second_event = Event.create!(
      slug: "list-view-series-second",
      source_fingerprint: "test::public::list-view-series::second",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    build_homepage_genre_enrichment(event: first_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: second_event, genres: [ "Rock" ])

    get events_url(filter: "all")

    assert_response :success
    assert_select ".genre-lane-card .event-series-badge", minimum: 1
    assert_select ".section-slider-list .event-series-badge", count: 0
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
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "needs_review",
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success
    assert_not_includes response.body, hidden_event.artist_name
  end

  test "search shows future unpublished events for authenticated users" do
    hidden_event = Event.create!(
      slug: "auth-visible-draft-event",
      source_fingerprint: "test::public::auth-visible-draft",
      title: "Auth Visible Draft Event",
      artist_name: "Auth Visible Draft Search Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
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
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    sign_in_as(@user)

    get search_url(filter: "all", q: "Auth Visible Draft Search")

    assert_response :success
    assert_includes response.body, hidden_event.artist_name
    assert_includes response.body, matching_published_event.artist_name
    assert_includes response.body, "event-card-admin-controls"
    assert_includes response.body, "/backend/events?event_id=#{hidden_event.id}&amp;status=#{hidden_event.status}"
    assert_select "#event-grid article.event-listing-card > .event-card-admin-controls", minimum: 1
    assert_select "#event-grid article.event-listing-card > a .event-card-admin-controls", count: 0
  end

  test "search redirects authenticated users to a scheduled unpublished search result" do
    scheduled_event = Event.create!(
      slug: "auth-hidden-scheduled-search-event",
      source_fingerprint: "test::public::auth-hidden-scheduled-search",
      title: "Scheduled Search Event",
      artist_name: "Scheduled Search Artist",
      start_at: 14.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 2.days.from_now,
      source_snapshot: {}
    )

    sign_in_as(@user)

    get search_url(filter: "all", q: "Scheduled Search Artist")

    assert_redirected_to event_url(scheduled_event.slug)
    assert_equal "ready_for_publish", scheduled_event.reload.status
  end

  test "index groups backend navigation links into a burger menu for authenticated users" do
    sign_in_as(@user)

    get events_url(filter: "all")

    assert_response :success
    assert_select ".app-nav-backend-menu[data-controller='backend-nav-menu']", count: 1
    assert_select ".app-nav-backend-toggle[aria-controls='app-nav-backend-menu']", text: /Backend/
    assert_select "#app-nav-backend-menu .app-nav-link", text: "Events"
    assert_select "#app-nav-backend-menu .app-nav-link", text: "Präsentatoren"
    assert_select "#app-nav-backend-menu .app-nav-link", text: "News"
    assert_select "#app-nav-backend-menu .app-nav-link", text: "Queue"
    assert_select "#app-nav-backend-menu .app-nav-link", text: "Passwort"
    assert_select "#app-nav-backend-menu .app-nav-link", text: "Logout"
    assert_match(/Events.*News.*Präsentatoren.*Venues.*Queue.*Passwort.*Logout/m, response.body)
    assert_select ".app-nav-links-group-separated", count: 0
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
      promoter_id: AppSetting.sks_promoter_ids.first,
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
      promoter_id: AppSetting.sks_promoter_ids.first,
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
    highlights_section = document.at_css("section.home-featured-section")
    all_events_section = document.css("section.genre-lane-section").find do |section|
      section.at_css("h2")&.text == "alles aus stuttgart"
    end
    tagestipp_section = document.css("section.genre-lane-section").find do |section|
      section.at_css("h2")&.text == "Tagestipp"
    end

    assert highlights_section.present?, "expected Highlights section to be rendered"
    assert all_events_section.present?, "expected all events section to be rendered"
    assert tagestipp_section.present?, "expected Tagestipp section to be rendered"

    highlight_names = highlights_section.css(".home-featured-track .event-card-copy h2").map(&:text)
    all_event_names = all_events_section.css(".genre-lane-card-name").map(&:text)
    tagestipp_names = tagestipp_section.css(".genre-lane-card-name").map(&:text)

    assert_includes highlight_names, published_highlight.artist_name
    assert_not_includes highlight_names, unpublished_highlight.artist_name
    assert_includes all_event_names, published_slider.artist_name
    assert_not_includes all_event_names, unpublished_slider.artist_name
    assert_includes tagestipp_names, published_tagestipp.artist_name
    assert_not_includes tagestipp_names, unpublished_tagestipp.artist_name
  end

  test "index hides scheduled published events in homepage sections for authenticated users" do
    sign_in_as(@user)

    scheduled_highlight = Event.create!(
      slug: "auth-homepage-scheduled-highlight",
      source_fingerprint: "test::public::auth-homepage::scheduled-highlight",
      title: "Auth Homepage Scheduled Highlight",
      artist_name: "Auth Homepage Scheduled Highlight Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      highlighted: true,
      status: "published",
      published_at: 2.days.from_now,
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    highlights_section = document.at_css("section.home-featured-section")
    highlight_names = highlights_section.css(".home-featured-track .event-card-copy h2").map(&:text)

    assert_not_includes highlight_names, scheduled_highlight.artist_name
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

  test "homepage renders promotion banner at the top when configured" do
    Event.create!(
      slug: "promotion-banner-highlight-event",
      source_fingerprint: "test::homepage::promotion-banner-highlight",
      title: "Promotion Banner Highlight",
      artist_name: "Promotion Banner Highlight Artist",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      primary_source: "eventim",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    blog_post = BlogPost.create!(
      title: "Großer Promo-Post",
      teaser: "Teaser",
      body: "<div>Promo</div>",
      author: @user,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @user
    )
    blog_post.promotion_banner_image.attach(png_upload(filename: "homepage-banner.png"))
    blog_post.update!(promotion_banner: true)

    get events_url

    assert_response :success
    assert_select ".promotion-banner h2", text: "Großer Promo-Post"
    assert_select ".promotion-banner a[href='#{news_path(blog_post.slug)}']"

    document = Nokogiri::HTML.parse(response.body)
    shell_children = document.css("section.public-shell > *")
    highlights_index = shell_children.index { |node| node.name == "section" && node["class"].to_s.include?("home-featured-section") }
    promotion_index = shell_children.index { |node| node.name == "article" && node["class"].to_s.include?("promotion-banner") }

    assert highlights_index.present?, "expected Highlights section to be rendered"
    assert promotion_index.present?, "expected Promotion Banner to be rendered"
    assert_equal 0, promotion_index
    assert_operator promotion_index, :<, highlights_index
  end

  test "homepage renders event promotion banner above highlights when no news banner is configured" do
    Event.create!(
      slug: "homepage-event-promotion-only-highlight",
      source_fingerprint: "test::homepage::event-promotion-only-highlight",
      title: "Promotion Only Highlight",
      artist_name: "Promotion Only Highlight Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event = Event.create!(
      slug: "homepage-event-promotion-only-banner",
      source_fingerprint: "test::homepage::event-promotion-only-banner",
      title: "Promotion Only Banner Event",
      artist_name: "Promotion Only Banner Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promotion_banner_kicker_text: "Event Tipp",
      promotion_banner_cta_text: "Zum Event",
      source_snapshot: {}
    )
    create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)
    event.update!(promotion_banner: true)

    get events_url

    assert_response :success
    assert_select ".promotion-banner-event h2", text: "Promotion Only Banner Artist"

    document = Nokogiri::HTML.parse(response.body)
    shell_children = document.css("section.public-shell > *")
    highlights_index = shell_children.index { |node| node.name == "section" && node["class"].to_s.include?("home-featured-section") }
    event_banner_index = shell_children.index { |node| node.name == "article" && node["class"].to_s.include?("promotion-banner-event") }
    news_banner_index = shell_children.index { |node| node.name == "article" && node["class"].to_s.include?("promotion-banner") && !node["class"].to_s.include?("promotion-banner-event") }

    assert_equal 0, event_banner_index
    assert_equal event_banner_index + 1, highlights_index
    assert_nil news_banner_index
  end

  test "homepage renders event promotion banner before news banner at the top" do
    Event.create!(
      slug: "homepage-event-promotion-highlight",
      source_fingerprint: "test::homepage::event-promotion-highlight",
      title: "Promotion Highlight",
      artist_name: "Promotion Highlight Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event = Event.create!(
      slug: "homepage-event-promotion-banner",
      source_fingerprint: "test::homepage::event-promotion-banner",
      title: "Promotion Banner Event",
      artist_name: "Promotion Banner Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promotion_banner_kicker_text: "Event Tipp",
      promotion_banner_cta_text: "Zum Event",
      source_snapshot: {}
    )
    create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)
    event.update!(promotion_banner: true)

    blog_post = BlogPost.create!(
      title: "Großer Promo-Post",
      teaser: "Teaser",
      body: "<div>Promo</div>",
      author: @user,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @user
    )
    blog_post.promotion_banner_image.attach(png_upload(filename: "homepage-banner.png"))
    blog_post.update!(promotion_banner: true)

    get events_url

    assert_response :success
    assert_select ".promotion-banner-event h2", text: "Promotion Banner Artist"
    assert_select ".promotion-banner-event .promotion-banner-event-title", text: "Promotion Banner Event"
    assert_select ".promotion-banner-event .promotion-banner-kicker", text: "Event Tipp"
    assert_select ".promotion-banner-event .promotion-banner-cta", text: "Zum Event"
    assert_select ".promotion-banner-event a[href='#{event_path(event.slug)}']"
    assert_select ".promotion-banner:not(.promotion-banner-event) a[href='#{news_path(blog_post.slug)}']"

    document = Nokogiri::HTML.parse(response.body)
    shell_children = document.css("section.public-shell > *")
    highlights_index = shell_children.index { |node| node.name == "section" && node["class"].to_s.include?("home-featured-section") }
    event_banner_index = shell_children.index { |node| node.name == "article" && node["class"].to_s.include?("promotion-banner-event") }
    news_banner_index = shell_children.index { |node| node.name == "article" && node["class"].to_s.include?("promotion-banner") && !node["class"].to_s.include?("promotion-banner-event") }

    assert_equal 0, event_banner_index
    assert_equal event_banner_index + 1, news_banner_index
    assert_operator event_banner_index, :<, highlights_index
    assert_operator news_banner_index, :<, highlights_index
  end

  test "homepage renders custom promotion banner texts from blog post" do
    Event.create!(
      slug: "promotion-banner-copy-event",
      source_fingerprint: "test::homepage::promotion-banner-copy",
      title: "Promotion Banner Copy",
      artist_name: "Promotion Banner Copy Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      primary_source: "eventim",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    blog_post = BlogPost.create!(
      title: "Promo mit Copy",
      teaser: "Teaser",
      body: "<div>Promo</div>",
      author: @user,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @user,
      promotion_banner_kicker_text: "Lesetipp",
      promotion_banner_cta_text: "Beitrag öffnen",
      promotion_banner_background_color: "#18333A"
    )
    blog_post.promotion_banner_image.attach(png_upload(filename: "homepage-banner-copy.png"))
    blog_post.update!(promotion_banner: true)

    get events_url

    assert_response :success
    assert_select ".promotion-banner-kicker", text: "Lesetipp"
    assert_select ".promotion-banner-cta", text: "Beitrag öffnen"
    assert_select ".promotion-banner-news[style*='--promotion-banner-background: #18333A']"
    assert_select ".promotion-banner-link-light[style='background: var(--promotion-banner-background)']"
  end

  test "homepage falls back to the default news promotion banner background color" do
    Event.create!(
      slug: "promotion-banner-default-color-highlight-event",
      source_fingerprint: "test::homepage::promotion-banner-default-color-highlight",
      title: "Promotion Banner Default Color Highlight",
      artist_name: "Promotion Banner Default Color Highlight Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      primary_source: "eventim",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event = Event.create!(
      slug: "promotion-banner-default-color-event",
      source_fingerprint: "test::homepage::promotion-banner-default-color-event",
      title: "Promotion Banner Default Color Event",
      artist_name: "Promotion Banner Default Color Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promotion_banner_kicker_text: "Event Tipp",
      promotion_banner_cta_text: "Zum Event",
      source_snapshot: {}
    )
    create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)
    event.update!(promotion_banner: true)

    blog_post = BlogPost.create!(
      title: "Promo mit Defaultfarbe",
      teaser: "Teaser",
      body: "<div>Promo</div>",
      author: @user,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @user
    )
    blog_post.promotion_banner_image.attach(png_upload(filename: "homepage-banner-default-color.png"))
    blog_post.update!(promotion_banner: true)

    get events_url

    assert_response :success
    assert_select ".promotion-banner-news[style*='--promotion-banner-background: #E0F7F2']"
    assert_select ".promotion-banner-link-dark[style='background: var(--promotion-banner-background)']"
    assert_select ".promotion-banner-event .promotion-banner-link-dark[style='background: var(--promotion-banner-background)']", count: 1
  end

  test "homepage renders custom promotion banner background color from event" do
    Event.create!(
      slug: "promotion-banner-event-color-highlight",
      source_fingerprint: "test::homepage::promotion-banner-event-color-highlight",
      title: "Promotion Banner Event Color Highlight",
      artist_name: "Promotion Banner Event Color Highlight Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event = Event.create!(
      slug: "promotion-banner-event-color",
      source_fingerprint: "test::homepage::promotion-banner-event-color",
      title: "Promotion Banner Event Color",
      artist_name: "Promotion Banner Event Color Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promotion_banner_kicker_text: "Event Tipp",
      promotion_banner_cta_text: "Zum Event",
      promotion_banner_background_color: "#18333A",
      source_snapshot: {}
    )
    create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)
    event.update!(promotion_banner: true)

    get events_url

    assert_response :success
    assert_select ".promotion-banner-event[style*='--promotion-banner-background: #18333A']"
    assert_select ".promotion-banner-event .promotion-banner-link-light[style='background: var(--promotion-banner-background)']"
  end

  test "homepage falls back to the default event promotion banner background color" do
    Event.create!(
      slug: "promotion-banner-event-default-highlight",
      source_fingerprint: "test::homepage::promotion-banner-event-default-highlight",
      title: "Promotion Banner Event Default Highlight",
      artist_name: "Promotion Banner Event Default Highlight Artist",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event = Event.create!(
      slug: "promotion-banner-event-default",
      source_fingerprint: "test::homepage::promotion-banner-event-default",
      title: "Promotion Banner Event Default",
      artist_name: "Promotion Banner Event Default Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)
    event.update!(promotion_banner: true)

    get events_url

    assert_response :success
    assert_select ".promotion-banner-event[style*='--promotion-banner-background: #E0F7F2']"
    assert_select ".promotion-banner-event .promotion-banner-link-dark[style='background: var(--promotion-banner-background)']"
  end

  test "homepage renders optimized promotion banner image" do
    banner_time = Time.zone.local(2026, 4, 6, 12, 0, 0)
    expected_path = nil

    with_media_proxy do
      travel_to banner_time do
        highlight = Event.create!(
          slug: "promotion-banner-optimized-highlight-event",
          source_fingerprint: "test::homepage::promotion-banner-optimized-highlight",
          title: "Promotion Banner Optimized Highlight",
          artist_name: "Promotion Banner Optimized Highlight Artist",
          start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0),
          venue: "Porsche-Arena",
          city: "Stuttgart",
          promoter_id: AppSetting.sks_promoter_ids.first,
          primary_source: "eventim",
          status: "published",
          published_at: 2.days.ago,
          source_snapshot: {}
        )

        create_event_image(event: highlight, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

        blog_post = BlogPost.create!(
          title: "Optimierter Promo-Post",
          teaser: "Teaser",
          body: "<div>Inhalt</div>",
          author: @user,
          status: "published",
          published_at: 1.hour.ago,
          published_by: @user
        )
        blog_post.promotion_banner_image.attach(
          io: StringIO.new(solid_png_binary(width: 2200, height: 1400)),
          filename: "homepage-banner-large.png",
          content_type: "image/png"
        )
        blog_post.update!(promotion_banner: true)

        get events_url(filter: "all")
        expected_path = PublicMediaUrl.path_for(blog_post.processed_optimized_image_variant(:promotion_banner_image))
      end
    end

    assert_response :success
    assert_includes response.body, expected_path
    refute_includes response.body, "/rails/active_storage/"
    document = Nokogiri::HTML.parse(response.body)
    promotion_banner_image = document.at_css(".promotion-banner:not(.promotion-banner-event) .promotion-banner-image")
    assert_not_nil promotion_banner_image
    assert_equal "eager", promotion_banner_image["loading"]
    assert_equal "high", promotion_banner_image["fetchpriority"]
    assert_equal "async", promotion_banner_image["decoding"]
    assert_includes promotion_banner_image["style"], "left:"
    assert_includes promotion_banner_image["style"], "top:"
    assert_includes promotion_banner_image["style"], "width:"
    assert_includes promotion_banner_image["style"], "height:"
  end

  test "homepage falls back to original news promotion banner image when optimized proxy path is unavailable" do
    banner_time = Time.zone.local(2026, 4, 6, 12, 0, 0)
    expected_path = nil

    with_media_proxy do
      travel_to banner_time do
        highlight = Event.create!(
          slug: "promotion-banner-news-fallback-highlight-event",
          source_fingerprint: "test::homepage::promotion-banner-news-fallback-highlight",
          title: "Promotion Banner News Fallback Highlight",
          artist_name: "Promotion Banner News Fallback Highlight Artist",
          start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0),
          venue: "Porsche-Arena",
          city: "Stuttgart",
          promoter_id: AppSetting.sks_promoter_ids.first,
          primary_source: "eventim",
          status: "published",
          published_at: 2.days.ago,
          source_snapshot: {}
        )

        create_event_image(event: highlight, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

        blog_post = BlogPost.create!(
          title: "Promo-Post mit Variant-Fallback",
          teaser: "Teaser",
          body: "<div>Inhalt</div>",
          author: @user,
          status: "published",
          published_at: 1.hour.ago,
          published_by: @user
        )
        blog_post.promotion_banner_image.attach(
          io: StringIO.new(solid_png_binary(width: 2200, height: 1400)),
          filename: "homepage-banner-fallback.png",
          content_type: "image/png"
        )
        blog_post.update!(promotion_banner: true)

        with_variant_proxy_path_unavailable do |original_path_for|
          get events_url(filter: "all")
          expected_path = original_path_for.call(blog_post.promotion_banner_image)
        end
      end
    end

    assert_response :success
    refute_includes response.body, "/rails/active_storage/"
    document = Nokogiri::HTML.parse(response.body)
    promotion_banner_image = document.at_css(".promotion-banner:not(.promotion-banner-event) .promotion-banner-image")
    assert_not_nil promotion_banner_image
    assert_equal expected_path, promotion_banner_image["src"]
  end

  test "homepage renders event promotion banner defaults and optimized event image" do
    event = Event.create!(
      slug: "homepage-event-promotion-banner-defaults",
      source_fingerprint: "test::homepage::event-promotion-banner-defaults",
      title: "Default Banner Event",
      artist_name: "Default Banner Artist",
      start_at: 7.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    image = create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)
    event.update!(promotion_banner: true)

    expected_path = nil

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        get events_url(filter: "all")
        expected_path = PublicMediaUrl.path_for(image.processed_optimized_variant)
      end
    end

    assert_response :success
    assert_select ".promotion-banner-event .promotion-banner-kicker", text: "Promotion"
    assert_select ".promotion-banner-event .promotion-banner-cta", text: "Zum Event"
    assert_includes response.body, expected_path
    refute_includes response.body, "/rails/active_storage/"
  end

  test "homepage falls back to original event image when optimized proxy path is unavailable" do
    event = Event.create!(
      slug: "homepage-event-promotion-banner-event-image-fallback",
      source_fingerprint: "test::homepage::event-promotion-banner-event-image-fallback",
      title: "Fallback Banner Event",
      artist_name: "Fallback Banner Artist",
      start_at: 7.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promotion_banner: true,
      source_snapshot: {}
    )
    image = create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

    expected_path = nil

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        with_variant_proxy_path_unavailable do |original_path_for|
          get events_url(filter: "all")
          expected_path = original_path_for.call(image.file)
        end
      end
    end

    assert_response :success
    refute_includes response.body, "/rails/active_storage/"
    document = Nokogiri::HTML.parse(response.body)
    promotion_banner_image = document.at_css(".promotion-banner-event .promotion-banner-image")
    assert_not_nil promotion_banner_image
    assert_equal expected_path, promotion_banner_image["src"]
  end

  test "homepage prefers dedicated event promotion banner image when present" do
    event = Event.create!(
      slug: "homepage-event-promotion-banner-dedicated-image",
      source_fingerprint: "test::homepage::event-promotion-banner-dedicated-image",
      title: "Dedicated Banner Event",
      artist_name: "Dedicated Banner Artist",
      start_at: 7.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promotion_banner: true,
      promotion_banner_image_copyright: "Foto: Banner",
      promotion_banner_image_focus_x: 18,
      promotion_banner_image_focus_y: 72,
      promotion_banner_image_zoom: 145,
      source_snapshot: {}
    )
    create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1, sub_text: "Fallback Credit")
    event.promotion_banner_image.attach(
      io: StringIO.new(solid_png_binary(width: 1600, height: 900)),
      filename: "event-promotion-banner.png",
      content_type: "image/png"
    )

    expected_path = nil

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        get events_url(filter: "all")
        expected_path = PublicMediaUrl.path_for(event.processed_optimized_promotion_banner_image_variant)
      end
    end

    assert_response :success
    assert_includes response.body, expected_path
    refute_includes response.body, "/rails/active_storage/"
    assert_select ".promotion-banner-event .promotion-banner-credit", text: "Foto: Banner"
    refute_includes response.body, "Fallback Credit"
    document = Nokogiri::HTML.parse(response.body)
    promotion_banner_image = document.at_css(".promotion-banner-event .promotion-banner-image")
    assert_not_nil promotion_banner_image
    assert_equal "eager", promotion_banner_image["loading"]
    assert_equal "high", promotion_banner_image["fetchpriority"]
    assert_equal "async", promotion_banner_image["decoding"]
    assert_includes promotion_banner_image["style"], "left:"
    assert_includes promotion_banner_image["style"], "top:"
    assert_includes promotion_banner_image["style"], "width:"
    assert_includes promotion_banner_image["style"], "height:"
  end

  test "homepage falls back to rails storage media urls when media proxy is unavailable" do
    event = Event.create!(
      slug: "homepage-strict-media-proxy-guard",
      source_fingerprint: "test::homepage::strict-media-proxy-guard",
      title: "Strict Media Proxy Guard",
      artist_name: "Strict Media Proxy Guard Artist",
      start_at: 7.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promotion_banner: true,
      source_snapshot: {}
    )
    create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO, grid_variant: EventImage::GRID_VARIANT_1X1)

    blog_post = BlogPost.create!(
      title: "Strict Proxy Blog Banner",
      teaser: "Teaser",
      body: "<div>Inhalt</div>",
      author: @user,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @user
    )
    blog_post.promotion_banner_image.attach(
      io: StringIO.new(solid_png_binary(width: 2200, height: 1400)),
      filename: "strict-proxy-homepage-banner.png",
      content_type: "image/png"
    )
    blog_post.update!(promotion_banner: true)

    with_media_proxy(enabled: false) do
      get events_url(filter: "all")
    end

    assert_response :success
    assert_includes response.body, "/rails/active_storage/"
    document = Nokogiri::HTML.parse(response.body)
    assert_not_nil document.at_css(".promotion-banner:not(.promotion-banner-event) .promotion-banner-image[src*='/rails/active_storage/']")
    assert_not_nil document.at_css(".promotion-banner-event .promotion-banner-image[src*='/rails/active_storage/']")
  end

  test "homepage skips event promotion banner without event image" do
    event = Event.create!(
      slug: "homepage-event-promotion-banner-without-image",
      source_fingerprint: "test::homepage::event-promotion-banner-without-image",
      title: "Banner ohne Bild",
      artist_name: "Banner ohne Bild Artist",
      start_at: 7.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promotion_banner: true,
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success
    assert_select ".promotion-banner-event a[href='#{event_path(event.slug)}']", count: 0
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

  test "index includes manually highlighted non-sks events in homepage highlights" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)

    highlighted_event = Event.create!(
      slug: "homepage-highlight-manual-non-sks",
      source_fingerprint: "test::homepage::highlight::manual-non-sks",
      title: "Homepage Highlight Manual Non SKS",
      artist_name: "Manual Highlight Artist",
      start_at: future_start,
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "99999",
      highlighted: true,
      source_snapshot: {}
    )

    get events_url

    assert_response :success
    assert_select ".home-featured-track", text: /#{Regexp.escape(highlighted_event.artist_name)}/
  end

  test "index places manually highlighted events first in homepage highlights" do
    highlighted_event = Event.create!(
      slug: "homepage-highlight-later",
      source_fingerprint: "test::homepage::highlight::later",
      title: "Homepage Highlight Later",
      artist_name: "Highlight Later Artist",
      start_at: 12.days.from_now.change(hour: 21, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "99999",
      highlighted: true,
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
      promoter_id: AppSetting.sks_promoter_ids.second,
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
      promoter_id: AppSetting.sks_promoter_ids.last,
      source_snapshot: {}
    )

    get events_url

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    highlights_section = document.at_css("section.home-featured-section")

    assert highlights_section.present?, "expected Highlights section to be rendered"

    names = highlights_section.css(".home-featured-track .event-card-copy h2").map(&:text)

    assert_equal [ highlighted_event.artist_name, earlier_event.artist_name, middle_event.artist_name ], names.first(3)
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
    assert_select ".lane-header.lane-header--editorial", count: 1
    assert_select "section.genre-lane-section", text: /alles aus stuttgart/ do
      assert_select ".genre-lane-card-name", text: reservix_event.artist_name
      assert_select ".genre-lane-card-name", text: late_reservix_event.artist_name
      assert_select ".genre-lane-card-name", text: eventim_event.artist_name, count: 0
    end
  end

  test "index limits the all events slider to 15 reservix events" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)
    included_event_names = []
    excluded_event_name = nil

    101.times do |index|
      artist_name = "Reservix Limited Artist #{index}"
      included_event_names << artist_name if index < 15
      excluded_event_name = artist_name if index == 15

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
    slider_section = document.css("section.genre-lane-section").find do |section|
      section.at_css("h2")&.text == "alles aus stuttgart"
    end

    assert slider_section.present?, "expected all events slider section to be rendered"

    names = slider_section.css(".genre-lane-card-name").map(&:text)

    assert_equal 15, names.size
    assert_includes names, included_event_names.first
    assert_includes names, included_event_names.last
    assert_not_includes names, excluded_event_name
  end

  test "index keeps the event series badge in all events slider when the second series event is outside the limit" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)
    series = EventSeries.create!(origin: "manual", name: "Wiener Klassik")

    target_event = Event.create!(
      slug: "reservix-limited-series-target",
      source_fingerprint: "test::homepage::reservix::limited-series::target",
      title: "Lyrische Welten",
      artist_name: "David Aaron Carpenter - Viola; Vladimir Fanshil - Leitung",
      start_at: future_start,
      venue: "Liederhalle Beethoven-Saal",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    99.times do |index|
      Event.create!(
        slug: "reservix-limited-series-filler-#{index}",
        source_fingerprint: "test::homepage::reservix::limited-series::filler::#{index}",
        title: "Reservix Filler #{index}",
        artist_name: "Reservix Filler Artist #{index}",
        start_at: future_start + (index + 1).minutes,
        venue: "Venue #{index}",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        primary_source: "reservix",
        source_snapshot: {}
      )
    end

    Event.create!(
      slug: "reservix-limited-series-outside-limit",
      source_fingerprint: "test::homepage::reservix::limited-series::outside-limit",
      title: "Lyrische Welten",
      artist_name: "Wang Wie - Klavier; Raphael Merlin - Leitung",
      start_at: future_start + 100.minutes,
      venue: "Liederhalle Beethoven-Saal",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "reservix",
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    slider_section = document.css("section.genre-lane-section").find do |section|
      section.at_css("h2")&.text == "alles aus stuttgart"
    end

    assert slider_section.present?, "expected all events slider section to be rendered"

    target_card = slider_section.css("article.genre-lane-card").find do |card|
      card.at_css(".genre-lane-card-name")&.text == target_event.artist_name
    end

    assert target_card.present?, "expected the target event card to be rendered in the all events slider"
    assert_equal "Event-Reihe", target_card.at_css(".event-series-badge")&.text.to_s.strip
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
      promoter_id: AppSetting.sks_promoter_ids.first,
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
    tagestipp_section = document.css("section.genre-lane-section").find do |section|
      section.at_css("h2")&.text == "Tagestipp"
    end

    assert tagestipp_section.present?, "expected Tagestipp section to be rendered"
    assert tagestipp_section.at_css(".lane-header.lane-header--tagestipp").present?, "expected Tagestipp header variant"

    names = tagestipp_section.css(".genre-lane-card-name").map(&:text)

    assert_equal "Tagestipp Filler Artist 9", names.first
    assert_includes names, today_event.artist_name
    assert_includes names, sks_today_event.artist_name
    assert_includes names, late_today_event.artist_name
    assert_not_includes names, reservix_today_event.artist_name
    assert_not_includes names, tomorrow_event.artist_name
  end

  test "tagestipp shows event series badge when the series is globally visible via a past event" do
    today_start = Time.zone.now.change(hour: 20, min: 0, sec: 0)
    series = EventSeries.create!(origin: "manual", name: "Marvel Reihe")
    today_event = Event.create!(
      slug: "tagestipp-series-today",
      source_fingerprint: "test::homepage::tagestipp::series::today",
      title: "Marvel heute",
      artist_name: "Marvel Reihe",
      start_at: today_start,
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      primary_source: "eventim",
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )
    Event.create!(
      slug: "tagestipp-series-past",
      source_fingerprint: "test::homepage::tagestipp::series::past",
      title: "Marvel gestern",
      artist_name: "Marvel Reihe",
      start_at: 1.day.ago.change(hour: 20),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 3.days.ago,
      primary_source: "eventim",
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    get events_url(filter: "all")

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    tagestipp_section = document.css("section.genre-lane-section").find do |section|
      section.at_css("h2")&.text == "Tagestipp"
    end

    assert tagestipp_section.present?, "expected Tagestipp section to be rendered"

    target_card = tagestipp_section.css("article.genre-lane-card").find do |card|
      card.at_css(".genre-lane-card-name")&.text == today_event.artist_name
    end

    assert target_card.present?, "expected the series event to be rendered in Tagestipp"
    assert_equal "Event-Reihe", target_card.at_css(".event-series-badge")&.text.to_s.strip
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

  test "index renders the search filter in the app nav" do
    placeholder_phrases = Public::EventsHelper::PUBLIC_SEARCH_PLACEHOLDER_PHRASES
    placeholder_sequence = Public::EventsHelper::PUBLIC_SEARCH_PLACEHOLDER_SEQUENCE

    get events_url(filter: "all", view: "list")

    assert_response :success
    assert_select ".app-nav-search .public-search-filter", count: 1
    assert_select ".app-nav-search .public-search-filter[action='#{search_path}']"
    form = css_select(".app-nav-search .public-search-filter").first
    input = css_select(".app-nav-search .public-search-input").first

    assert_equal placeholder_sequence.to_json, form["data-public-search-placeholder-sequence-value"]
    assert_equal placeholder_phrases.first, input["placeholder"]
    assert_select ".app-nav-search .public-search-placeholder", count: 1
    assert_select ".app-nav-search [data-public-search-target='placeholderText']", text: placeholder_phrases.first
    assert_select ".app-nav-search [data-public-search-target='placeholderCursor']", count: 1

    assert_select ".public-filter-row", count: 0
    assert_select ".public-view-toggle", count: 0
    assert_select "input[name='view']", count: 0
  end

  test "index redirects old search links to the dedicated search page" do
    get events_url(filter: "all", q: @published_event.artist_name)

    assert_redirected_to search_url(q: @published_event.artist_name)
  end

  test "search redirects to detail page when search has a single result" do
    get search_url(filter: "all", q: @published_event.artist_name)

    assert_redirected_to event_url(@published_event.slug)
  end

  test "search redirects to detail page for normalized umlaut queries" do
    event = Event.create!(
      slug: "search-normalized-umlaut",
      source_fingerprint: "test::search::normalized::umlaut",
      title: "Die Ärzte live",
      artist_name: "Die Ärzte",
      start_at: 18.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_url(filter: "all", q: "Die Aerzte")

    assert_redirected_to event_url(event.slug)
  end

  test "search ignores the default sks filter for a single result" do
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

    get search_url(q: non_sks_event.artist_name)

    assert_redirected_to event_url(non_sks_event.slug)
  end

  test "search renders flat search results without homepage sliders for multiple matches" do
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

    get search_url(filter: "all", q: "Search Cluster")

    assert_response :success
    assert_select ".lane-header.lane-header--search", count: 1
    assert_select ".lane-header.lane-header--search .slider-window-bar", count: 1
    assert_select ".lane-header.lane-header--search .lane-header-title", text: "Suchergebnisse"
    assert_select ".lane-header.lane-header--search .lane-header-meta", text: /Search Cluster/
    assert_select ".lane-header.lane-header--search .lane-header-meta", text: /2 Ergebnisse/
    assert_select ".slider-view-toggle", count: 0
    assert_select "#event-grid article.event-listing-card", count: 2
    assert_select "#event-grid article.genre-lane-card", count: 0
    assert_includes response.body, first_event.title
    assert_includes response.body, second_event.title
    assert_includes response.body, "Suchergebnisse"
    assert_not_includes response.body, "alles aus stuttgart"
    assert_not_includes response.body, reservix_slider_event.artist_name
    assert_not_includes response.body, "Tagestipp"
    assert_not_includes response.body, tagestipp_event.artist_name
    assert_not_includes response.body, @published_event.artist_name
    assert_not_includes response.body, "Mehr Events laden"
    assert_select "#events-pagination", count: 0
    assert_select ".newsletter-signup-section", count: 1
  end

  test "search renders all matching results without pagination" do
    13.times do |index|
      Event.create!(
        slug: "search-all-results-#{index}",
        source_fingerprint: "test::search::all-results::#{index}",
        title: "Search All Results #{index}",
        artist_name: "Search All Results",
        start_at: (20 + index).days.from_now.change(hour: 20, min: 0, sec: 0),
        venue: "Venue #{index}",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        source_snapshot: {}
      )
    end

    get search_url(q: "Search All Results")

    assert_response :success
    assert_select "#event-grid article.event-listing-card", count: 13
    assert_select "#event-grid article.genre-lane-card", count: 0
    assert_select "#events-pagination", count: 0
  end

  test "search renders a friendly empty state without matches" do
    get search_url(q: "Absolut Unfindbarer Suchbegriff")

    assert_response :success
    assert_select ".lane-header.lane-header--search .lane-header-meta", text: /Absolut Unfindbarer Suchbegriff/
    assert_select ".lane-header.lane-header--search .lane-header-meta", text: /0 Ergebnisse/
    assert_includes response.body, "Sorry, nix gefunden"
    assert_includes response.body, "Zu „Absolut Unfindbarer Suchbegriff“ haben wir aktuell keine Events gefunden."
  end

  test "search redirects to homepage for punctuation only query" do
    get search_url(q: " ... !!! ")

    assert_redirected_to events_url
  end

  test "index redirects punctuation only old search links back to homepage" do
    get events_url(q: " ... !!! ")

    assert_redirected_to events_url
  end

  test "highlight list rows do not render ticket links" do
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
      promoter_id: AppSetting.sks_promoter_ids.first,
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
    assert_not_includes response.body, "https://easyticket.example/tickets"
    assert_not_includes response.body, "https://eventim.example/tickets"
  end

  test "search result event cards show an ausverkauft ribbon for sold out leading offers" do
    event = Event.create!(
      slug: "search-sold-out-ribbon",
      source_fingerprint: "test::public::search::sold-out-ribbon",
      title: "Search Ribbon Tour",
      artist_name: "Search Ribbon Artist",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-search-ribbon-1",
      ticket_url: "https://easyticket.example/search-ribbon",
      sold_out: true,
      priority_rank: 0,
      metadata: {}
    )

    event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/search-ribbon",
      sold_out: false,
      priority_rank: 0,
      metadata: {}
    )

    Event.create!(
      slug: "search-sold-out-ribbon-companion",
      source_fingerprint: "test::public::search::sold-out-ribbon-companion",
      title: "Search Ribbon Companion",
      artist_name: "Search Ribbon Collective",
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_url(q: "Search Ribbon")

    assert_response :success
    assert_select "#search_card_event_#{event.id} .event-sold-out-ribbon", text: "Ausverkauft"
    assert_select "#search_card_event_#{event.id} .event-card-ticket-overlay", count: 0
  end

  test "search result event cards do not show an ausverkauft ribbon when the leading imported offer is available" do
    event = Event.create!(
      slug: "search-available-no-ribbon",
      source_fingerprint: "test::public::search::available-no-ribbon",
      title: "Available Ribbon Tour",
      artist_name: "Available Ribbon Artist",
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-search-ribbon-2",
      ticket_url: "https://easyticket.example/search-available",
      sold_out: false,
      priority_rank: 0,
      metadata: {}
    )

    event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/search-sold-out",
      sold_out: true,
      priority_rank: 0,
      metadata: {}
    )

    Event.create!(
      slug: "search-available-no-ribbon-companion",
      source_fingerprint: "test::public::search::available-no-ribbon-companion",
      title: "Available Ribbon Companion",
      artist_name: "Available Ribbon Collective",
      start_at: 13.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_url(q: "Available Ribbon")

    assert_response :success
    assert_select "#search_card_event_#{event.id} .event-sold-out-ribbon", count: 0
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
    assert_select ".event-detail-cta .event-detail-cta-button", text: "Tickets bei Easy Ticket sichern"
  end

  test "show renders sold out note when imported primary offer is sold out even if a manual offer exists" do
    event = Event.create!(
      slug: "show-imported-sold-out-blocks-manual",
      source_fingerprint: "test::public::show::imported-sold-out-blocks-manual",
      title: "Sold Out Priority",
      artist_name: "Sold Out Artist",
      start_at: 16.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-sold-out-123",
      ticket_url: "https://easyticket.example/sold-out",
      sold_out: true,
      priority_rank: 0,
      metadata: {}
    )

    event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/still-open",
      sold_out: false,
      priority_rank: 0,
      metadata: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_select ".event-detail-cta", count: 1
    assert_includes response.body, "Ausverkauft"
    assert_not_includes response.body, "https://manual.example/still-open"
    assert_not_includes response.body, "https://easyticket.example/sold-out"
    assert_not_includes response.body, "Tickets sichern"
  end

  test "show renders sold out note and sks hint for sold out sks events" do
    event = Event.create!(
      slug: "show-sks-sold-out-message",
      source_fingerprint: "test::public::show::sks-sold-out-message",
      title: "SKS Sold Out Message",
      artist_name: "SKS Sold Out Artist",
      start_at: 16.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      sks_sold_out_message: "Bitte bei SKS nach Restkarten fragen",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-sold-out-message-123",
      ticket_url: "https://easyticket.example/sold-out-message",
      sold_out: true,
      priority_rank: 0,
      metadata: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_select ".event-detail-cta", count: 1
    assert_includes response.body, "Ausverkauft"
    assert_includes response.body, "Bitte bei SKS nach Restkarten fragen"
    assert_not_includes response.body, "Tickets sichern"
    assert_not_includes response.body, "https://easyticket.example/sold-out-message"
  end

  test "show renders generic sold out note for non sks events" do
    event = Event.create!(
      slug: "show-non-sks-sold-out-message",
      source_fingerprint: "test::public::show::non-sks-sold-out-message",
      title: "Non SKS Sold Out Message",
      artist_name: "Non SKS Sold Out Artist",
      start_at: 16.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: "99999",
      sks_sold_out_message: "Bitte bei SKS nach Restkarten fragen",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "non-sks-sold-out-message-123",
      ticket_url: "https://easyticket.example/non-sks-sold-out-message",
      sold_out: true,
      priority_rank: 0,
      metadata: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_select ".event-detail-cta", count: 1
    assert_includes response.body, "Ausverkauft"
    assert_not_includes response.body, "Bitte bei SKS nach Restkarten fragen"
    assert_not_includes response.body, "Tickets sichern"
  end

  test "show renders generic sold out note for sold out sks events without message" do
    event = Event.create!(
      slug: "show-sks-sold-out-without-message",
      source_fingerprint: "test::public::show::sks-sold-out-without-message",
      title: "SKS Sold Out Without Message",
      artist_name: "SKS Sold Out Without Message Artist",
      start_at: 16.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "sks-sold-out-without-message-123",
      ticket_url: "https://easyticket.example/sks-sold-out-without-message",
      sold_out: true,
      priority_rank: 0,
      metadata: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_select ".event-detail-cta", count: 1
    assert_includes response.body, "Ausverkauft"
    assert_not_includes response.body, "Tickets sichern"
    assert_not_includes response.body, "https://easyticket.example/sks-sold-out-without-message"
  end

  test "genre lane cards render sold out ribbon above the event series badge while list rows stay unchanged" do
    create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])

    series = EventSeries.create!(origin: "manual", name: "Ribbon Reihe")
    event = Event.create!(
      slug: "genre-lane-sold-out-ribbon",
      source_fingerprint: "test::public::genre-lane::sold-out-ribbon",
      title: "Genre Ribbon Tour",
      artist_name: "Genre Ribbon Artist",
      start_at: 13.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )
    companion_event = Event.create!(
      slug: "genre-lane-sold-out-ribbon-companion",
      source_fingerprint: "test::public::genre-lane::sold-out-ribbon-companion",
      title: "Genre Ribbon Tour II",
      artist_name: "Genre Ribbon Artist",
      start_at: 14.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    build_homepage_genre_enrichment(event: event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: companion_event, genres: [ "Rock" ])

    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-genre-ribbon-1",
      ticket_url: "https://easyticket.example/genre-ribbon",
      sold_out: true,
      priority_rank: 0,
      metadata: {}
    )

    get events_url(filter: "all")

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    card = document.css("article.genre-lane-card").find do |node|
      node.at_css(".genre-lane-card-name")&.text == event.artist_name
    end

    assert card.present?, "expected sold out genre lane card to be rendered"
    assert_equal 1, card.css(".event-sold-out-ribbon").size
    assert_equal 1, card.css(".event-series-badge").size
    assert_equal 0, card.css(".genre-lane-card-ticket-overlay").size
    assert_select ".event-listing-card .event-sold-out-ribbon", count: 0
  end

  test "show renders published event by slug" do
    extra_genre = genres(:jazz)
    @published_event.genres << genres(:pop)
    @published_event.genres << extra_genre

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Events"
    assert_includes response.body, "Published Artist"
    assert_select ".event-detail-time-line", text: /Beginn:\s*\d{2}:\d{2}\s*Uhr/
    assert_select ".event-detail-meta-line", text: /LKA Longhorn/
    assert_select ".event-detail-time-line", text: /Einlass/, count: 0
    assert_includes response.body, "Preis: 45 EUR"
    assert_select ".event-detail-tag", text: "Jazz"
    assert_select ".event-detail-tag", text: "Pop"
    assert_select ".event-detail-tag", text: "Rock"
    assert_select "script[type='application/ld+json']", /Published Artist/
  end

  test "show renders related genre lane in chronological order without sks or highlight promotion" do
    snapshot, rock_group, = create_homepage_genre_snapshot
    regular_event = Event.create!(
      slug: "show-related-genre-regular",
      source_fingerprint: "test::public::show-related-genre::regular",
      title: "Show Related Regular",
      artist_name: "Related Regular Artist",
      start_at: 8.days.from_now.change(hour: 18, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    sks_event = Event.create!(
      slug: "show-related-genre-sks",
      source_fingerprint: "test::public::show-related-genre::sks",
      title: "Show Related SKS",
      artist_name: "Related SKS Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    highlighted_event = Event.create!(
      slug: "show-related-genre-highlighted",
      source_fingerprint: "test::public::show-related-genre::highlighted",
      title: "Show Related Highlighted",
      artist_name: "Related Highlighted Artist",
      start_at: 8.days.from_now.change(hour: 22, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      highlighted: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    unpublished_event = Event.create!(
      slug: "show-related-genre-unpublished",
      source_fingerprint: "test::public::show-related-genre::unpublished",
      title: "Show Related Unpublished",
      artist_name: "Related Unpublished Artist",
      start_at: 8.days.from_now.change(hour: 21, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      source_snapshot: {}
    )
    past_event = Event.create!(
      slug: "show-related-genre-past",
      source_fingerprint: "test::public::show-related-genre::past",
      title: "Show Related Past",
      artist_name: "Related Past Artist",
      start_at: 2.days.ago.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 5.days.ago,
      source_snapshot: {}
    )

    assert_equal snapshot.id, LlmGenreGrouping::Lookup.selected_snapshot.id

    build_homepage_genre_enrichment(event: @published_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: regular_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: sks_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: highlighted_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: unpublished_event, genres: [ "Rock" ])
    build_homepage_genre_enrichment(event: past_event, genres: [ "Rock" ])

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-related-list h2", text: "Das könnte dir auch gefallen"
    assert_select ".event-detail-related-list .event-listing-link strong", text: regular_event.artist_name
    assert_select ".event-detail-related-list .event-listing-link strong", text: sks_event.artist_name
    assert_select ".event-detail-related-list .event-listing-link strong", text: highlighted_event.artist_name
    assert_select ".event-detail-related-list .event-listing-link strong", text: @published_event.artist_name, count: 0
    assert_select ".event-detail-related-list .event-listing-link strong", text: unpublished_event.artist_name, count: 0
    assert_select ".event-detail-related-list .event-listing-link strong", text: past_event.artist_name, count: 0

    related_names = Nokogiri::HTML.parse(response.body).css(".event-detail-related-list .event-listing-link strong").map(&:text)

    assert_equal [
      regular_event.artist_name,
      sks_event.artist_name,
      highlighted_event.artist_name
    ], related_names.first(3)
  end

  test "show limits related genre lane to ten events" do
    snapshot, = create_homepage_genre_snapshot

    assert_equal snapshot.id, LlmGenreGrouping::Lookup.selected_snapshot.id

    build_homepage_genre_enrichment(event: @published_event, genres: [ "Rock" ])

    related_events = 12.times.map do |index|
      event = Event.create!(
        slug: "show-related-genre-limit-#{index}",
        source_fingerprint: "test::public::show-related-genre::limit::#{index}",
        title: "Show Related Limit #{index}",
        artist_name: "Related Limit Artist #{index}",
        start_at: (index + 2).days.from_now.change(hour: 20, min: 0, sec: 0),
        venue: "Im Wizemann",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        source_snapshot: {}
      )
      build_homepage_genre_enrichment(event: event, genres: [ "Rock" ])
      event
    end

    get event_url(@published_event.slug)

    assert_response :success

    related_names = Nokogiri::HTML.parse(response.body).css(".event-detail-related-list .event-listing-link strong").map(&:text)

    assert_equal 10, related_names.size
    assert_equal related_events.first(10).map(&:artist_name), related_names
    assert_not_includes related_names, related_events.last(2).first.artist_name
    assert_not_includes related_names, related_events.last.artist_name
  end

  test "show does not render related genre lane without selected snapshot or additional matches" do
    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-related-list", count: 0

    snapshot, = create_homepage_genre_snapshot
    build_homepage_genre_enrichment(event: @published_event, genres: [ "Rock" ])
    AppSetting.where(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY).delete_all
    AppSetting.reset_cache!

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-related-list", count: 0
  end

  test "show renders the full event series lane before the related genre lane" do
    create_homepage_genre_snapshot
    build_homepage_genre_enrichment(event: @published_event, genres: [ "Rock" ])

    related_event = Event.create!(
      slug: "show-related-genre-series-neighbor",
      source_fingerprint: "test::public::show-related-genre::series-neighbor",
      title: "Related Genre Neighbor",
      artist_name: "Related Genre Neighbor",
      start_at: 9.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    build_homepage_genre_enrichment(event: related_event, genres: [ "Rock" ])

    series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
    @published_event.update!(event_series: series, event_series_assignment: "manual")
    past_event = Event.create!(
      slug: "show-series-past",
      source_fingerprint: "test::public::show-series::past",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 4.days.ago.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 10.days.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )
    future_event = Event.create!(
      slug: "show-series-future",
      source_fingerprint: "test::public::show-series::future",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 6.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    get event_url(@published_event.slug)

    assert_response :success
    series_section = css_select("section.genre-lane-section").find do |section|
      section.at_css(".lane-header-kicker")&.text.to_s.include?("Event-Reihe")
    end
    assert_not_nil series_section
    assert_equal series.name, series_section.at_css("h2")&.text.to_s.strip
    assert_equal 3, series_section.css(".genre-lane-card-name").size
    assert_equal 0, series_section.css(".event-series-badge").size
    assert_includes series_section.text, I18n.l(future_event.start_at.to_date, format: "%d.%m.%Y")
    assert_includes series_section.text, I18n.l(past_event.start_at.to_date, format: "%d.%m.%Y")

    series_index = response.body.index(@published_event.title)
    genre_index = response.body.index("Das könnte dir auch gefallen")
    assert_operator series_index, :<, genre_index
  end

  test "show does not render the event series lane when only one public event is visible" do
    series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
    @published_event.update!(event_series: series, event_series_assignment: "manual")
    Event.create!(
      slug: "show-series-hidden-draft",
      source_fingerprint: "test::public::show-series::hidden-draft",
      title: "A Tribute to Frida Kahlo",
      artist_name: "Viva la Vida",
      start_at: 6.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      event_series: series,
      event_series_assignment: "manual",
      source_snapshot: {}
    )

    get event_url(@published_event.slug)

    assert_response :success
    series_section = css_select("section.genre-lane-section").find do |section|
      section.at_css(".lane-header-kicker")&.text.to_s.include?("Event-Reihe")
    end
    assert_nil series_section
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

  test "show renders youtube fallback link when video is not embeddable" do
    @published_event.update!(youtube_url: "https://www.youtube.com/@publishedartist")

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-links a", text: /YouTube/
    assert_select ".event-detail-links a[href='https://www.youtube.com/@publishedartist']"
    assert_select "template iframe", count: 0
    assert_not_includes response.body, "YouTube laden"
  end

  test "show does not render dangling comma when city is blank" do
    @published_event.update!(city: nil)

    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, @published_event.venue
    assert_not_includes response.body, "#{@published_event.venue}, </span>"
    assert_no_match(/#{Regexp.escape(@published_event.venue)}\s*,\s*<\/span>/, response.body)
  end

  test "show does not duplicate city when venue already contains it" do
    @published_event.update!(venue: "Im Wizemann (Halle) Stuttgart", city: "Stuttgart")

    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, "Im Wizemann (Halle) Stuttgart"
    assert_not_includes response.body, "Im Wizemann (Halle) Stuttgart, Stuttgart"
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
    assert_select ".event-detail-time-line", text: /Einlass 18:30 Uhr/
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

  test "show renders support section when support is present" do
    event = Event.create!(
      slug: "published-event-with-support",
      source_fingerprint: "test::public::published::support",
      title: "Published Event With Support",
      artist_name: "Published Artist With Support",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      event_info: "Öffentliche Beschreibung",
      support: "Support Act",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_select ".event-detail-support-line", text: "Support: Support Act"
    assert_select "section.event-detail-panel h2", text: "Support", count: 0
  end

  test "show renders llm enrichment fallbacks and extra sections" do
    event = Event.create!(
      slug: "published-event-with-llm-enrichment",
      source_fingerprint: "test::public::published::llm-enrichment",
      title: "Published Event With LLM Enrichment",
      artist_name: "Published Artist With LLM Enrichment",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      event_info: nil,
      homepage_url: nil,
      instagram_url: nil,
      facebook_url: nil,
      youtube_url: nil,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    event.create_llm_enrichment!(
      event_description: "LLM Event- und Artist-Beschreibung",
      venue_description: "LLM Venue Beschreibung",
      homepage_link: "https://llm-homepage.example",
      instagram_link: "https://instagram.example/llm-band",
      facebook_link: "https://facebook.example/llm-band",
      youtube_link: "https://www.youtube.com/watch?v=llm123",
      genre: [ "Indie", "Synthpop" ],
      source_run: import_runs(:one),
      model: "gpt-test",
      prompt_version: "v1",
      raw_response: {}
    )
    event.venue_record.update!(
      description: "Venue Modell Beschreibung",
      external_url: "https://venue.example/im-wizemann",
      address: "Quellenstraße 7, 70376 Stuttgart"
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "LLM Event- und Artist-Beschreibung"
    assert_includes response.body, "Venue Modell Beschreibung"
    assert_includes response.body, "https://venue.example/im-wizemann"
    assert_includes response.body, "Quellenstraße 7, 70376 Stuttgart"
    assert_includes response.body, "https://llm-homepage.example"
    assert_includes response.body, "https://instagram.example/llm-band"
    assert_includes response.body, "https://facebook.example/llm-band"
    assert_includes response.body, "https://www.youtube.com/embed/llm123"
    assert_includes response.body, "Indie"
    assert_includes response.body, "Synthpop"
  end

  test "show avoids duplicate subtitle and genre section" do
    event = Event.create!(
      slug: "published-event-with-duplicate-title",
      source_fingerprint: "test::public::published::duplicate-title",
      title: "Kuult",
      artist_name: "Kuult",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Kulturquartier Stuttgart",
      city: "Stuttgart",
      event_info: "Fallschirmvertrauen - Tour 2026\n\nFallschirmvertrauen - Tour 2026",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    event.create_llm_enrichment!(
      genre: [ "Pop", "Deutschpop" ],
      source_run: import_runs(:one),
      model: "gpt-test",
      prompt_version: "v1",
      raw_response: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_select "h1", text: "Kuult"
    assert_select ".event-detail-title", count: 0
    assert_select ".event-detail-tag", text: "Pop"
    assert_select ".event-detail-tag", text: "Deutschpop"
    assert_select "h2", text: "Genres", count: 0
    assert_select ".event-detail-copy-block-primary p", text: "Fallschirmvertrauen - Tour 2026", count: 1
  end

  test "show renders meta description and canonical seo tags" do
    get event_url(@published_event.slug)

    assert_response :success
    assert_select "meta[name='description']", count: 1
    assert_select "meta[property='og:url'][content=?]", event_url(@published_event.slug)
    assert_select "link[rel='canonical'][href=?]", event_url(@published_event.slug)
  end

  test "show wraps event detail copy into hero-aligned text columns" do
    @published_event.update!(event_info: "Erster Absatz.\n\nZweiter Absatz.\n\nDritter Absatz.")
    @published_event.create_llm_enrichment!(
      event_description: "Fallback Event Beschreibung",
      venue_description: "Venue links.\n\nVenue rechts.",
      source_run: import_runs(:one),
      model: "gpt-test",
      prompt_version: "v1",
      raw_response: {}
    )

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-copy-block", minimum: 2
    assert_select ".event-detail-copy-grid", count: 0
    assert_includes response.body, "Erster Absatz."
    assert_includes response.body, "Dritter Absatz."
    assert_includes response.body, "Rockclub in Stuttgart-Wangen."
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
    assert_select ".event-detail-organizer-brand img[alt='Russ Live']", count: 1
    assert_select ".event-detail-organizer-presenters", count: 0
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
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Veranstalterhinweise"
    assert_includes response.body, "Konfigurierter SKS Hinweis"
  end

  test "show includes edit link for authenticated users" do
    sign_in_as(@user)

    get event_url(@published_event.slug)

    assert_response :success
    expected_link = backend_events_path(status: @published_event.status, event_id: @published_event.id).gsub("&", "&amp;")
    assert_select ".event-detail-cta .event-detail-cta-button", text: "Tickets bei Easy Ticket sichern"
    assert_includes response.body, expected_link
    assert_select ".public-backend-shortcut.event-detail-edit-link", text: "Edit"
    assert_select ".event-detail-topbar-actions .event-detail-edit-link", count: 1
    assert_select ".event-detail-image-stage-shell .saved-event-button.saved-event-button-detail-image[data-controller='saved-event-toggle']", count: 1
  end

  test "show renders presenter logos inside organizer notes when presenters exist" do
    presenter_one = create_presenter(name: "Alpha Presenter")
    presenter_two = create_presenter(name: "Beta Presenter")
    @published_event.update!(
      organizer_notes: "Sichtbare Veranstalterhinweise",
      show_organizer_notes: true
    )
    @published_event.event_presenters.create!(presenter: presenter_two, position: 2)
    @published_event.event_presenters.create!(presenter: presenter_one, position: 1)
    create_event_image(event: @published_event, purpose: EventImage::PURPOSE_SLIDER)

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-presenters", count: 0
    assert_select ".event-detail-organizer-presenters", count: 1
    assert_select ".event-detail-organizer-partner-grid", count: 1
    assert_select ".event-detail-organizer-partner[href='#{presenter_one.external_url}']", count: 1
    assert_select ".event-detail-organizer-partner[href='#{presenter_two.external_url}']", count: 1
    assert_select ".event-detail-organizer-partner-image[alt='Alpha Presenter']", count: 1
    assert_select ".event-detail-organizer-partner-image[alt='Beta Presenter']", count: 1
    assert_includes response.body, rails_storage_proxy_path(presenter_one.detail_logo_variant, only_path: true)
    assert_includes response.body, rails_storage_proxy_path(presenter_two.detail_logo_variant, only_path: true)
    refute_includes response.body, "/rails/active_storage/blobs/redirect/"
  end

  test "show renders svg presenter logos via proxy path" do
    svg_presenter = create_presenter(name: "SVG Presenter", svg: true)
    @published_event.update!(
      organizer_notes: "Sichtbare Veranstalterhinweise",
      show_organizer_notes: true
    )
    @published_event.event_presenters.create!(presenter: svg_presenter, position: 1)

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-presenters", count: 0
    assert_select ".event-detail-organizer-partner-image[alt='SVG Presenter']", count: 1
    assert_includes response.body, rails_storage_proxy_path(svg_presenter.detail_logo_variant, only_path: true)
    refute_includes response.body, "/rails/active_storage/blobs/redirect/"
  end

  test "show renders a single presenter in the organizer partner grid" do
    presenter = create_presenter(name: "Solo Presenter")
    @published_event.update!(
      organizer_notes: "Sichtbare Veranstalterhinweise",
      show_organizer_notes: true
    )
    @published_event.event_presenters.create!(presenter:, position: 1)

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-organizer-presenters", count: 1
    assert_select ".event-detail-organizer-partner-grid", count: 1
    assert_select ".event-detail-organizer-partner[href='#{presenter.external_url}']", count: 1
    assert_select ".event-detail-organizer-partner-image[alt='Solo Presenter']", count: 1
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

  test "show returns not found for scheduled published events for guests" do
    event = Event.create!(
      slug: "scheduled-public-detail",
      source_fingerprint: "test::public::scheduled::detail",
      title: "Scheduled Public Detail",
      artist_name: "Scheduled Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 2.days.from_now,
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

  test "show renders scheduled published events for authenticated users with geplant badge" do
    sign_in_as(@user)

    event = Event.create!(
      slug: "scheduled-auth-detail",
      source_fingerprint: "test::public::scheduled::auth-detail",
      title: "Scheduled Auth Detail",
      artist_name: "Scheduled Auth Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 2.days.from_now,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Geplant"
    assert_select ".event-detail-badges-row .status-badge", text: "Geplant"
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

  test "show keeps working for published events after matching raw imports are deleted" do
    @past_published_event.update!(
      source_snapshot: {
        "sources" => [
          {
            "source" => "easyticket",
            "source_identifier" => "published-past-event:2026-01-10",
            "external_event_id" => "published-past-event",
            "raw_payload" => {
              "event_id" => "published-past-event",
              "date" => "2026-01-10",
              "title_1" => "Past Artist",
              "title_2" => "Past Published Event"
            }
          }
        ]
      }
    )
    raw_import = RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "published-past-event:2026-01-10",
      payload: {
        "event_id" => "published-past-event",
        "date" => "2026-01-10",
        "title_1" => "Past Artist",
        "title_2" => "Past Published Event",
        "loc_name" => "LKA Longhorn",
        "loc_city" => "Stuttgart"
      },
      detail_payload: {}
    )

    travel_to(Time.zone.parse("2026-04-15 10:00:00")) do
      Events::Retention::PrunePastRawEventImports.call
    end

    assert_not RawEventImport.exists?(raw_import.id)

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
    assert_includes response.body, "event-card-admin-controls"
    assert_includes response.body, "/backend/events?event_id=#{event.id}&amp;status=#{event.status}"
  end

  test "search overlay renders matching future events for guests" do
    matching_event = Event.create!(
      slug: "search-overlay-match",
      source_fingerprint: "test::public::search-overlay::match",
      title: "Electric Skyline Tour",
      artist_name: "Search Overlay Artist",
      start_at: 15.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    Event.create!(
      slug: "search-overlay-hidden-draft",
      source_fingerprint: "test::public::search-overlay::hidden-draft",
      title: "Electric Skyline Internal",
      artist_name: "Search Overlay Artist Draft",
      start_at: 16.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      source_snapshot: {}
    )

    get search_overlay_events_url(q: "Electric Skyline")

    assert_response :success
    assert_includes response.body, "Search Overlay Artist"
    assert_includes response.body, event_path(matching_event.slug, q: "Electric Skyline")
    assert_includes response.body, "Electric Skyline Tour"
    assert_not_includes response.body, "Search Overlay Artist Draft"
  end

  test "search overlay renders phrase suggestions for incomplete structured queries" do
    Event.create!(
      slug: "search-overlay-suggestion-fallback",
      source_fingerprint: "test::public::search-overlay::suggestion-fallback",
      title: "Diesen Montag Special",
      artist_name: "Fallback Artist",
      start_at: 15.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_overlay_events_url(q: "diesen Mo")

    assert_response :success
    assert_includes response.body, "Diesen Montag"
    assert_includes response.body, "Event-Treffer"
    assert_includes response.body, "Fallback Artist"
    assert_not_includes response.body, "passende zukünftige Events"
  end

  test "search overlay renders venue suggestions for structured venue fragments" do
    Venue.create!(name: "Porsche-Arena")
    Event.create!(
      slug: "search-overlay-venue-fallback",
      source_fingerprint: "test::public::search-overlay::venue-fallback",
      title: "Heute in der Porsche-Arena",
      artist_name: "Venue Fallback Artist",
      start_at: 16.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_overlay_events_url(q: "heute in der Po")

    assert_response :success
    assert_includes response.body, "Porsche-Arena"
    assert_includes response.body, "Event-Treffer"
    assert_includes response.body, "Venue Fallback Artist"
  end

  test "search overlay renders these week venue suggestions" do
    Venue.create!(name: "Goldmark's")
    Event.create!(
      slug: "search-overlay-diese-woche-goldmarks",
      source_fingerprint: "test::public::search-overlay::diese-woche-goldmarks",
      title: "Diese Woche Goldmarks",
      artist_name: "Diese Woche Fallback Artist",
      start_at: 3.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Goldmark's",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_overlay_events_url(q: "diese Woche im Goldmarks")

    assert_response :success
    assert_includes response.body, "Goldmark&#39;s"
  end

  test "strict structured venue filtering excludes unrelated venues on the search page" do
    travel_to(Time.zone.parse("2026-04-07 10:00:00")) do
      matching_event = Event.create!(
        slug: "search-overlay-goldmarks-match",
        source_fingerprint: "test::public::search-overlay::goldmarks-match",
        title: "Goldmark's Weekend",
        artist_name: "Goldmark Overlay Artist",
        start_at: Time.zone.parse("2026-04-11 20:00:00"),
        venue: "Goldmark´s Stuttgart",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        source_snapshot: {}
      )
      Event.create!(
        slug: "search-overlay-goldmarks-other",
        source_fingerprint: "test::public::search-overlay::goldmarks-other",
        title: "Other Stuttgart Weekend",
        artist_name: "Other Stuttgart Overlay Artist",
        start_at: Time.zone.parse("2026-04-11 21:00:00"),
        venue: "Stuttgart Arena",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        source_snapshot: {}
      )

      get search_overlay_events_url(q: "Dieses Wochenende im Goldmark")

      assert_response :success
      assert_includes response.body, "Goldmark´s Stuttgart"
      assert_not_includes response.body, "Goldmark Overlay Artist"

      get search_url(q: "Dieses Wochenende im Goldmark´s Stuttgart")

      assert_redirected_to event_url(matching_event.slug)
    end
  end

  test "search overlay renders structured event previews for complete time phrases" do
    travel_to(Time.zone.parse("2026-04-07 10:00:00")) do
      Event.create!(
        slug: "search-overlay-heute",
        source_fingerprint: "test::public::search-overlay::heute",
        title: "Heute Konzert",
        artist_name: "Heute Artist",
        start_at: Time.zone.parse("2026-04-07 20:00:00"),
        venue: "Im Wizemann",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        source_snapshot: {}
      )
      Event.create!(
        slug: "search-overlay-morgen",
        source_fingerprint: "test::public::search-overlay::morgen",
        title: "Morgen Konzert",
        artist_name: "Morgen Artist",
        start_at: Time.zone.parse("2026-04-08 20:00:00"),
        venue: "Im Wizemann",
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        source_snapshot: {}
      )

      get search_overlay_events_url(q: "heute")

      assert_response :success
      assert_includes response.body, "Heute Artist"
      assert_not_includes response.body, "Morgen Artist"
    end
  end

  test "search overlay matches normalized punctuation and whitespace variants" do
    matching_event = Event.create!(
      slug: "search-overlay-normalized-match",
      source_fingerprint: "test::public::search-overlay::normalized-match",
      title: "Live in Stuttgart",
      artist_name: "AC/DC",
      start_at: 17.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_overlay_events_url(q: " AC   DC   Live ")

    assert_response :success
    assert_includes response.body, matching_event.artist_name
    assert_includes response.body, event_path(matching_event.slug, q: "AC   DC   Live")
  end

  test "search overlay prioritizes sks and highlighted matches before regular matches" do
    regular_event = Event.create!(
      slug: "search-overlay-priority-regular",
      source_fingerprint: "test::public::search-overlay::priority-regular",
      title: "Priority Search Tour",
      artist_name: "Regular Priority Artist",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: "99999",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    highlighted_event = Event.create!(
      slug: "search-overlay-priority-highlighted",
      source_fingerprint: "test::public::search-overlay::priority-highlighted",
      title: "Priority Search Tour",
      artist_name: "Highlighted Priority Artist",
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: "99999",
      highlighted: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    sks_event = Event.create!(
      slug: "search-overlay-priority-sks",
      source_fingerprint: "test::public::search-overlay::priority-sks",
      title: "Priority Search Tour",
      artist_name: "SKS Priority Artist",
      start_at: 15.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_overlay_events_url(q: "Priority Search")

    assert_response :success
    assert_operator response.body.index(sks_event.artist_name), :<, response.body.index(regular_event.artist_name)
    assert_operator response.body.index(highlighted_event.artist_name), :<, response.body.index(regular_event.artist_name)
  end

  test "search overlay renders prioritized recommendations without query" do
    promotion_event = Event.create!(
      slug: "search-overlay-initial-promotion",
      source_fingerprint: "test::public::search-overlay::initial-promotion",
      title: "Initial Search Promotion",
      artist_name: "Initial Promotion Artist",
      start_at: 6.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      promotion_banner: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    highlighted_event = Event.create!(
      slug: "search-overlay-initial-highlighted",
      source_fingerprint: "test::public::search-overlay::initial-highlighted",
      title: "Initial Search Highlight",
      artist_name: "Initial Highlight Artist",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      highlighted: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    highlighted_sks_event = Event.create!(
      slug: "search-overlay-initial-highlighted-sks",
      source_fingerprint: "test::public::search-overlay::initial-highlighted-sks",
      title: "Initial Search Highlighted SKS",
      artist_name: "Initial Highlighted SKS Artist",
      start_at: 4.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      highlighted: true,
      promoter_id: AppSetting.sks_promoter_ids.first,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    sks_event = Event.create!(
      slug: "search-overlay-initial-sks",
      source_fingerprint: "test::public::search-overlay::initial-sks",
      title: "Initial Search SKS",
      artist_name: "Initial SKS Artist",
      start_at: 3.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Porsche-Arena",
      city: "Stuttgart",
      promoter_id: AppSetting.sks_promoter_ids.last,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    Event.create!(
      slug: "search-overlay-initial-regular",
      source_fingerprint: "test::public::search-overlay::initial-regular",
      title: "Initial Search Regular",
      artist_name: "Initial Regular Artist",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_overlay_events_url

    assert_response :success
    assert_includes response.body, promotion_event.artist_name
    assert_includes response.body, highlighted_event.artist_name
    assert_includes response.body, highlighted_sks_event.artist_name
    assert_includes response.body, sks_event.artist_name
    assert_not_includes response.body, "Initial Regular Artist"

    document = Nokogiri::HTML.parse(response.body)
    artists = document.css(".public-search-result-artist").map(&:text)

    assert_equal promotion_event.artist_name, artists.first
    assert_operator artists.index(highlighted_event.artist_name), :<, artists.index(sks_event.artist_name)
    assert_operator artists.index(highlighted_sks_event.artist_name), :<, artists.index(sks_event.artist_name)
    assert_equal 1, artists.count { |artist_name| artist_name == highlighted_sks_event.artist_name }
  end

  test "search overlay falls back to highlights for punctuation only query" do
    highlighted_event = Event.create!(
      slug: "search-overlay-punctuation-highlighted",
      source_fingerprint: "test::public::search-overlay::punctuation-highlighted",
      title: "Initial Search Highlight",
      artist_name: "Initial Highlight Artist",
      start_at: 7.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      highlighted: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    Event.create!(
      slug: "search-overlay-punctuation-regular",
      source_fingerprint: "test::public::search-overlay::punctuation-regular",
      title: "Initial Search Regular",
      artist_name: "Initial Regular Artist",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_overlay_events_url(q: " ... !!! ")

    assert_response :success
    assert_includes response.body, highlighted_event.artist_name
    assert_not_includes response.body, "Initial Regular Artist"
    assert_not_includes response.body, "Keine Treffer"
  end

  test "search overlay limits initial recommendations to ten events" do
    promotion_event = Event.create!(
      slug: "search-overlay-initial-limit-promotion",
      source_fingerprint: "test::public::search-overlay::initial-limit::promotion",
      title: "Initial Limit Promotion",
      artist_name: "Initial Limit Promotion Artist",
      start_at: 3.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Venue Promotion",
      city: "Stuttgart",
      promotion_banner: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    4.times do |index|
      Event.create!(
        slug: "search-overlay-initial-highlight-limit-#{index}",
        source_fingerprint: "test::public::search-overlay::initial-highlight-limit::#{index}",
        title: "Initial Highlight Limit #{index}",
        artist_name: "Initial Highlight Limit Artist #{index}",
        start_at: (10 + index).days.from_now.change(hour: 20, min: 0, sec: 0),
        venue: "Highlight Venue #{index}",
        city: "Stuttgart",
        highlighted: true,
        status: "published",
        published_at: 1.day.ago,
        source_snapshot: {}
      )
    end

    7.times do |index|
      Event.create!(
        slug: "search-overlay-initial-sks-limit-#{index}",
        source_fingerprint: "test::public::search-overlay::initial-sks-limit::#{index}",
        title: "Initial SKS Limit #{index}",
        artist_name: "Initial SKS Limit Artist #{index}",
        start_at: (20 + index).days.from_now.change(hour: 20, min: 0, sec: 0),
        venue: "SKS Venue #{index}",
        city: "Stuttgart",
        promoter_id: AppSetting.sks_promoter_ids.first,
        status: "published",
        published_at: 1.day.ago,
        source_snapshot: {}
      )
    end

    get search_overlay_events_url

    assert_response :success
    assert_select ".public-search-overlay-list li", count: 10
    assert_includes response.body, promotion_event.artist_name
    assert_not_includes response.body, "Initial SKS Limit Artist 5"
    assert_not_includes response.body, "Initial SKS Limit Artist 6"
  end

  test "search overlay filters initial recommendations by selected date" do
    selected_date = 11.days.from_now.to_date
    matching_event = Event.create!(
      slug: "search-overlay-initial-date-match",
      source_fingerprint: "test::public::search-overlay::initial-date-match",
      title: "Date Filter Highlight",
      artist_name: "Date Match Artist",
      start_at: selected_date.in_time_zone.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      highlighted: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    Event.create!(
      slug: "search-overlay-initial-date-other",
      source_fingerprint: "test::public::search-overlay::initial-date-other",
      title: "Date Filter Highlight Later",
      artist_name: "Date Other Artist",
      start_at: (selected_date + 1.day).in_time_zone.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      highlighted: true,
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get search_overlay_events_url(event_date: selected_date.iso8601)

    assert_response :success
    assert_includes response.body, matching_event.artist_name
    assert_not_includes response.body, "Date Other Artist"
  end

  test "search overlay shows unpublished matching events for authenticated users" do
    sign_in_as(@user)

    unpublished_event = Event.create!(
      slug: "search-overlay-auth-draft",
      source_fingerprint: "test::public::search-overlay::auth-draft",
      title: "Members Only Draft Tour",
      artist_name: "Search Overlay Auth Artist",
      start_at: 14.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "needs_review",
      source_snapshot: {}
    )

    get search_overlay_events_url(q: "Members Only Draft")

    assert_response :success
    assert_includes response.body, unpublished_event.artist_name
    assert_includes response.body, event_path(unpublished_event.slug, q: "Members Only Draft")
  end

  test "search overlay shows scheduled unpublished matching events for authenticated users" do
    sign_in_as(@user)

    scheduled_event = Event.create!(
      slug: "search-overlay-auth-scheduled",
      source_fingerprint: "test::public::search-overlay::auth-scheduled",
      title: "Members Only Scheduled Tour",
      artist_name: "Search Overlay Scheduled Artist",
      start_at: 14.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 2.days.from_now,
      source_snapshot: {}
    )

    get search_overlay_events_url(q: "Members Only Scheduled")

    assert_response :success
    assert_includes response.body, scheduled_event.artist_name
    assert_equal "ready_for_publish", scheduled_event.reload.status
  end

  test "status update requires authentication" do
    patch status_event_url(@published_event.slug), params: { status: "needs_review" }

    assert_redirected_to new_session_url
  end

  test "authenticated user can update event status from public cards" do
    sign_in_as(@user)
    previous_published_at = @published_event.published_at

    patch status_event_url(@published_event.slug), params: { status: "needs_review", page: "1", filter: "all", event_date: "2026-06-01" }

    assert_redirected_to events_url(page: "1", event_date: "2026-06-01")
    assert_equal "needs_review", @published_event.reload.status
    assert_equal previous_published_at, @published_event.published_at
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

  test "show prefers editorial hero and renders hero rotator with slider images" do
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
    assert_select ".event-detail-image-figure-rotator[data-controller='hero-rotator lightbox'][data-hero-rotator-delay-value='3000']", count: 1
    assert_select ".event-detail-image-stage-shell.highlights-slider-viewport", count: 1
    assert_select ".event-detail-image-stage", count: 1
    assert_select ".event-detail-image-slide", count: 2
    assert_select ".event-detail-image-backdrop", count: 2
    assert_select ".event-detail-image-stage-shell .highlights-slider-arrow.highlights-slider-arrow-overlay", count: 2
    assert_select ".event-detail-image-stage-shell .highlights-slider-arrow-prev[data-action='hero-rotator#previous']", count: 1
    assert_select ".event-detail-image-stage-shell .highlights-slider-arrow-next[data-action='hero-rotator#next']", count: 1
    assert_select ".event-lightbox .highlights-slider-arrow.highlights-slider-arrow-overlay", count: 2
    assert_select ".event-lightbox .highlights-slider-arrow-prev[data-action='click->lightbox#previous']", count: 1
    assert_select ".event-lightbox .highlights-slider-arrow-next[data-action='click->lightbox#next']", count: 1
    assert_select ".event-detail-image-dot", count: 2
    assert_select ".event-detail-slider", count: 0
    assert_select ".event-lightbox", count: 1
    assert_includes response.body, rails_storage_proxy_path(hero_image.processed_optimized_variant, only_path: true)
    assert_includes response.body, rails_storage_proxy_path(slider_image.processed_optimized_variant, only_path: true)
    refute_includes response.body, "/rails/active_storage/blobs/redirect/"
  end

  test "show renders single event hero image in the shared stage with attached credit" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      sub_text: "Foto Max Mustermann",
      grid_variant: EventImage::GRID_VARIANT_1X1
    )

    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-image-figure .event-detail-image-stage.event-detail-image-stage-static", count: 1
    assert_select ".event-detail-image-stage .event-detail-image-picture img.event-detail-image", count: 1
    assert_select ".event-detail-image-figure > .event-detail-image-credit", text: "© Foto Max Mustermann"
  end

  test "show falls back to import image when no event image exists" do
    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, "https://example.com/published.jpg"
  end

  test "show renders the saved event toggle button on the detail image" do
    get event_url(@published_event.slug)

    assert_response :success
    assert_select ".event-detail-image-stage-shell .saved-event-button.saved-event-button-detail-image[data-controller='saved-event-toggle']", count: 1
    assert_includes response.body, @published_event.slug
  end

  test "index uses event image crop variant for grid tile size" do
    image = create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      grid_variant: EventImage::GRID_VARIANT_2X2,
      alt_text: "Grid 2x2 Alt"
    )

    expected_path = nil

    with_media_proxy do
      get events_url(filter: "all")
      expected_path = PublicMediaUrl.path_for(image.processed_optimized_variant)
    end

    assert_response :success
    assert_includes response.body, "event-card-grid-2-2"
    assert_includes response.body, "Grid 2x2 Alt"
    assert_includes response.body, expected_path
    refute_includes response.body, "/rails/active_storage/blobs/redirect/"
  end

  test "index uses event image crop variant outside the old pattern slot" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      grid_variant: EventImage::GRID_VARIANT_1X2,
      alt_text: "Grid 1x2 Alt"
    )

    with_media_proxy do
      get events_url(filter: "all")
    end

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

    with_media_proxy do
      get events_url(filter: "all")
    end

    assert_response :success
    assert_includes response.body, "event-card-grid-1-1"
    assert_includes response.body, "Eventbild Default Alt"
  end

  test "index renders the saved events lane slot on the homepage first page" do
    get events_url(filter: "all")

    assert_response :success
    assert_select "#saved-events-lane-slot[data-controller='saved-events-lane'][data-saved-events-lane-url-value='#{saved_lane_events_path}'][hidden]", count: 1
  end

  test "saved lane renders only valid future published events in chronological order" do
    later_event = create_public_event(
      slug: "saved-lane-later",
      artist_name: "Saved Lane Later",
      start_at: 9.days.from_now.change(hour: 21, min: 0, sec: 0)
    )
    earlier_event = create_public_event(
      slug: "saved-lane-earlier",
      artist_name: "Saved Lane Earlier",
      start_at: 5.days.from_now.change(hour: 19, min: 0, sec: 0)
    )
    unpublished_event = create_public_event(
      slug: "saved-lane-unpublished",
      artist_name: "Saved Lane Unpublished",
      start_at: 6.days.from_now.change(hour: 20, min: 0, sec: 0),
      status: "needs_review",
      published_at: nil
    )
    past_event = create_public_event(
      slug: "saved-lane-past",
      artist_name: "Saved Lane Past",
      start_at: 2.days.ago.change(hour: 20, min: 0, sec: 0)
    )

    get saved_lane_events_url, params: {
      slugs: [ later_event.slug, past_event.slug, "missing-event", earlier_event.slug, unpublished_event.slug ]
    }

    assert_response :success
    assert_includes response.body, "Deine Events"

    document = Nokogiri::HTML.fragment(response.body)
    rendered_names = document.css(".genre-lane-card-name").map(&:text)

    assert_equal [ earlier_event.artist_name, later_event.artist_name ], rendered_names
    assert_not_includes rendered_names, unpublished_event.artist_name
    assert_not_includes rendered_names, past_event.artist_name
  end

  test "saved lane returns an empty response when no valid saved events remain" do
    unpublished_event = create_public_event(
      slug: "saved-lane-empty-unpublished",
      artist_name: "Saved Lane Empty Unpublished",
      start_at: 6.days.from_now.change(hour: 20, min: 0, sec: 0),
      status: "needs_review",
      published_at: nil
    )
    past_event = create_public_event(
      slug: "saved-lane-empty-past",
      artist_name: "Saved Lane Empty Past",
      start_at: 2.days.ago.change(hour: 20, min: 0, sec: 0)
    )

    get saved_lane_events_url, params: { slugs: [ unpublished_event.slug, past_event.slug ] }

    assert_response :success
    assert_empty response.body.strip
  end

  test "index renders saved event toggle buttons for public event cards" do
    create_homepage_genre_snapshot(lane_slugs: [ "rock-alternative" ])
    build_homepage_genre_enrichment(event: @published_event, genres: [ "Rock" ])

    get events_url(filter: "all")

    assert_response :success
    assert_select ".event-card .saved-event-button[data-controller='saved-event-toggle']", minimum: 1
    assert_select ".genre-lane-card .saved-event-button[data-controller='saved-event-toggle']", minimum: 1
    assert_includes response.body, @published_event.slug
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

  def create_public_event(slug:, artist_name:, start_at:, status: "published", published_at: 1.day.ago)
    Event.create!(
      slug: slug,
      source_fingerprint: "test::public::events-controller::#{slug}",
      title: "#{artist_name} Title",
      artist_name: artist_name,
      start_at: start_at,
      venue: "Club Zentral",
      city: "Stuttgart",
      status: status,
      published_at: published_at,
      source_snapshot: {}
    )
  end

  def create_homepage_genre_snapshot(selected: true, lane_slugs: [ "rock-alternative", "pop-mainstream" ])
    run = import_sources(:two).import_runs.create!(
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )

    snapshot = run.create_llm_genre_grouping_snapshot!(
      active: false,
      requested_group_count: 30,
      effective_group_count: 2,
      source_genres_count: 2,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )

    rock_group = snapshot.groups.create!(position: 1, name: "Rock & Alternative", member_genres: [ "Rock" ])
    pop_group = snapshot.groups.create!(position: 2, name: "Pop & Mainstream", member_genres: [ "Pop" ])
    snapshot.create_homepage_genre_lane_configuration!(lane_slugs:)
    AppSetting.create!(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY, value: snapshot.id) if selected

    [ snapshot, rock_group, pop_group ]
  end

  def build_homepage_genre_enrichment(event:, genres:)
    EventLlmEnrichment.create!(
      event: event,
      source_run: import_runs(:one),
      genre: genres,
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )
  end

  def create_presenter(name:, svg: false)
    presenter = Presenter.new(
      name: name,
      external_url: "https://example.com/#{name.parameterize}"
    )
    presenter.logo.attach(svg ? create_svg_blob(filename: "#{name.parameterize}.svg") : create_uploaded_blob(filename: "#{name.parameterize}.png"))
    presenter.save!
    presenter
  end

  def create_svg_blob(filename:)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(<<~SVG),
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <rect width="16" height="16" fill="#000"/>
        </svg>
      SVG
      filename:,
      content_type: "image/svg+xml"
    )
  end

  def with_variant_proxy_path_unavailable
    original_path_for = PublicMediaUrl.method(:path_for)

    PublicMediaUrl.singleton_class.send(:define_method, :path_for) do |record|
      record.is_a?(ActiveStorage::VariantWithRecord) ? nil : original_path_for.call(record)
    end

    yield original_path_for
  ensure
    PublicMediaUrl.singleton_class.send(:define_method, :path_for, original_path_for) if original_path_for.present?
  end
end
