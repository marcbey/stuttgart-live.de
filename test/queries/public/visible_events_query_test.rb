require "test_helper"

class Public::VisibleEventsQueryTest < ActiveSupport::TestCase
  setup do
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [ "10135", "10136", "382" ])
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
  end

  test "filters to sks promoter ids" do
    matching_event = create_visible_event(title: "SKS Query", artist_name: "SKS Artist", promoter_id: AppSetting.sks_promoter_ids.first)
    create_visible_event(title: "Other Query", artist_name: "Other Artist", promoter_id: "99999")

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_SKS
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "includes manually highlighted events without sks promoter id" do
    sks_event = create_visible_event(title: "SKS Query", artist_name: "SKS Artist", promoter_id: AppSetting.sks_promoter_ids.first)
    highlighted_event = create_visible_event(title: "Manual Highlight", artist_name: "Manual Highlight Artist", promoter_id: "99999", highlighted: true)
    create_visible_event(title: "Other Query", artist_name: "Other Artist", promoter_id: "99999")

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_SKS
    ).call

    assert_equal [ sks_event, highlighted_event ], result.to_a
  end

  test "uses configured sks promoter ids" do
    AppSetting.find_by!(key: AppSetting::SKS_PROMOTER_IDS_KEY).update!(value: [ "77777" ])
    AppSetting.reset_cache!
    matching_event = create_visible_event(title: "Configured SKS Query", artist_name: "Configured Artist", promoter_id: "77777")
    create_visible_event(title: "Other SKS Query", artist_name: "Default Artist", promoter_id: "10135")

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_SKS
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "filters by event date and search query" do
    selected_date = 14.days.from_now.to_date
    matching_event = create_visible_event(
      title: "Irish Folk Night",
      artist_name: "The Query Band",
      start_at: selected_date.in_time_zone.change(hour: 20, min: 0, sec: 0)
    )
    create_visible_event(
      title: "Jazz Session",
      artist_name: "The Other Band",
      start_at: selected_date.in_time_zone.change(hour: 22, min: 0, sec: 0)
    )
    create_visible_event(
      title: "Irish Folk Night Late",
      artist_name: "The Query Band",
      start_at: (selected_date + 1.day).in_time_zone.change(hour: 20, min: 0, sec: 0)
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      event_date: selected_date,
      query: "irish"
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "matches german umlaut spellings via normalized query variants" do
    matching_event = create_visible_event(
      title: "Die Ärzte live",
      artist_name: "Die Ärzte"
    )
    create_visible_event(
      title: "Anderer Abend",
      artist_name: "Andere Band"
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "Die Aerzte"
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "matches punctuation and repeated whitespace via normalized query variants" do
    matching_event = create_visible_event(
      title: "Live in Stuttgart",
      artist_name: "AC/DC"
    )
    create_visible_event(
      title: "Live in Stuttgart",
      artist_name: "AC and Friends"
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: " AC   DC   Live "
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "matches normalized artist names through normalized_artist_name" do
    matching_event = create_visible_event(
      title: "Neues Album",
      artist_name: "FJØRT"
    )
    create_visible_event(
      title: "Andere Show",
      artist_name: "Andere Band"
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "fjort"
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "matches venue names across punctuation-only differences" do
    create_visible_event(
      title: "Night at Goldmark's",
      artist_name: "Punctuation Artist",
      venue_name: "Goldmark's"
    )
    create_visible_event(
      title: "Different Venue Night",
      artist_name: "Other Artist",
      venue_name: "LKA Longhorn"
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "goldmarks"
    ).call

    assert_equal [ "Punctuation Artist" ], result.map(&:artist_name)
  end

  test "matches genres without returning duplicate events" do
    matching_event = create_visible_event(
      title: "Heavy Night",
      artist_name: "Genre Artist"
    )
    matching_event.genres << Genre.create!(name: "Search Rock", slug: "search-rock")
    matching_event.genres << Genre.create!(name: "Search Progressive Rock", slug: "search-progressive-rock")

    create_visible_event(
      title: "Different Night",
      artist_name: "Other Artist"
    ).genres << Genre.create!(name: "Search Jazz", slug: "search-jazz")

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "search rock"
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "filters structured today queries by start_at" do
    travel_to(Time.zone.parse("2026-04-07 10:00:00")) do
      matching_event = create_visible_event(
        title: "Heute Konzert",
        artist_name: "Heute Artist",
        start_at: Time.zone.parse("2026-04-07 20:00:00")
      )
      create_visible_event(
        title: "Morgen Konzert",
        artist_name: "Morgen Artist",
        start_at: Time.zone.parse("2026-04-08 20:00:00")
      )

      result = Public::VisibleEventsQuery.new(
        scope: Event.published_live,
        filter: Public::VisibleEventsQuery::FILTER_ALL,
        query: "heute"
      ).call

      assert_equal [ matching_event ], result.to_a
    end
  end

  test "filters structured venue queries through matching venues" do
    travel_to(Time.zone.parse("2026-04-07 10:00:00")) do
      matching_event = create_visible_event(
        title: "Heute Im Wizemann",
        artist_name: "Venue Artist",
        start_at: Time.zone.parse("2026-04-07 20:00:00"),
        venue_name: "Im Wizemann"
      )
      create_visible_event(
        title: "Heute Porsche",
        artist_name: "Andere Venue",
        start_at: Time.zone.parse("2026-04-07 21:00:00"),
        venue_name: "Porsche-Arena"
      )

      result = Public::VisibleEventsQuery.new(
        scope: Event.published_live,
        filter: Public::VisibleEventsQuery::FILTER_ALL,
        query: "heute im Wizemann"
      ).call

      assert_equal [ matching_event ], result.to_a
    end
  end

  test "filters diese woche venue queries through matching venues" do
    travel_to(Time.zone.parse("2026-04-07 10:00:00")) do
      matching_event = create_visible_event(
        title: "Diese Woche Goldmarks",
        artist_name: "Diese Woche Artist",
        start_at: Time.zone.parse("2026-04-09 20:00:00"),
        venue_name: "Goldmark's"
      )
      create_visible_event(
        title: "Nächste Woche Goldmarks",
        artist_name: "Next Week Artist",
        start_at: Time.zone.parse("2026-04-14 20:00:00"),
        venue_name: "Goldmark's"
      )

      result = Public::VisibleEventsQuery.new(
        scope: Event.published_live,
        filter: Public::VisibleEventsQuery::FILTER_ALL,
        query: "diese Woche im Goldmarks"
      ).call

      assert_equal [ matching_event ], result.to_a
    end
  end

  test "structured venue queries do not broaden to unrelated fuzzy venues" do
    travel_to(Time.zone.parse("2026-04-07 10:00:00")) do
      matching_event = create_visible_event(
        title: "Goldmark's Weekend",
        artist_name: "Goldmark Artist",
        start_at: Time.zone.parse("2026-04-11 20:00:00"),
        venue_name: "Goldmark´s Stuttgart"
      )
      create_visible_event(
        title: "Other Stuttgart Weekend",
        artist_name: "Other Stuttgart Artist",
        start_at: Time.zone.parse("2026-04-11 21:00:00"),
        venue_name: "Stuttgart Arena"
      )

      result = Public::VisibleEventsQuery.new(
        scope: Event.published_live,
        filter: Public::VisibleEventsQuery::FILTER_ALL,
        query: "Dieses Wochenende im Goldmark´s Stuttgart"
      ).call

      assert_equal [ matching_event ], result.to_a
    end
  end

  test "weekend queries include friday events for matching venues" do
    travel_to(Time.zone.parse("2026-04-07 10:00:00")) do
      friday_event = create_visible_event(
        title: "Goldmark's Friday Weekend",
        artist_name: "Goldmark Friday Artist",
        start_at: Time.zone.parse("2026-04-10 20:00:00"),
        venue_name: "Goldmark´s Stuttgart"
      )
      create_visible_event(
        title: "Goldmark's Thursday",
        artist_name: "Goldmark Thursday Artist",
        start_at: Time.zone.parse("2026-04-09 20:00:00"),
        venue_name: "Goldmark´s Stuttgart"
      )

      result = Public::VisibleEventsQuery.new(
        scope: Event.published_live,
        filter: Public::VisibleEventsQuery::FILTER_ALL,
        query: "Am Wochenende im Goldmark´s Stuttgart"
      ).call

      assert_equal [ friday_event ], result.to_a
    end
  end

  test "returns none for incomplete structured queries" do
    create_visible_event(title: "Montag Konzert", artist_name: "Band")

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "diesen Mo"
    ).call

    assert_empty result
  end

  test "ignores punctuation only queries" do
    create_visible_event(title: "First Event", artist_name: "First Artist")
    create_visible_event(title: "Second Event", artist_name: "Second Artist", start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0))

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: " ... !!! "
    ).call

    assert_equal Event.published_live.to_a, result.to_a
  end

  test "prioritizes sks events in search results" do
    regular_event = create_visible_event(
      title: "Search Priority Night",
      artist_name: "Regular Search Artist",
      promoter_id: "99999",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0)
    )
    sks_event = create_visible_event(
      title: "Search Priority Night",
      artist_name: "SKS Search Artist",
      promoter_id: AppSetting.sks_promoter_ids.first,
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0)
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "Search Priority"
    ).call

    assert_equal [ sks_event, regular_event ], result.to_a
  end

  test "prioritizes highlighted events in search results" do
    regular_event = create_visible_event(
      title: "Highlight Priority Night",
      artist_name: "Regular Highlight Artist",
      promoter_id: "99999",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0)
    )
    highlighted_event = create_visible_event(
      title: "Highlight Priority Night",
      artist_name: "Highlighted Search Artist",
      promoter_id: "99999",
      highlighted: true,
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0)
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "Highlight Priority"
    ).call

    assert_equal [ highlighted_event, regular_event ], result.to_a
  end

  private

  def create_visible_event(title:, artist_name:, promoter_id: nil, highlighted: false, start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0), venue_name: "Im Wizemann")
    Event.create!(
      title: title,
      artist_name: artist_name,
      start_at: start_at,
      venue: venue_name,
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: promoter_id,
      highlighted: highlighted,
      source_fingerprint: SecureRandom.uuid,
      source_snapshot: {}
    )
  end
end
