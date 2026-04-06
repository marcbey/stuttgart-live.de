require "test_helper"

class Public::Events::HomepageGenreLanesBuilderTest < ActiveSupport::TestCase
  setup do
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [ "10135" ])
    AppSetting.reset_cache!

    run = import_sources(:two).import_runs.create!(
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )

    @snapshot = run.create_llm_genre_grouping_snapshot!(
      active: true,
      requested_group_count: 30,
      effective_group_count: 2,
      source_genres_count: 4,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )

    @rock_group = @snapshot.groups.create!(position: 1, name: "Rock & Alternative", member_genres: [ "Rock" ])
    @pop_group = @snapshot.groups.create!(position: 2, name: "Pop & Mainstream", member_genres: [ "Pop" ])
    AppSetting.create!(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY, value: @snapshot.id)
    @snapshot.create_homepage_genre_lane_configuration!(lane_slugs: [ @rock_group.slug, @pop_group.slug ])
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "builds lanes in configured order and ignores unknown or empty groups" do
    rock_event = build_lane_event(slug: "lane-rock", artist_name: "Rock Event", start_at: 10.days.from_now.change(hour: 20))
    build_lane_enrichment(event: rock_event, genres: [ "Rock" ])

    builder = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day),
      slugs: [ "missing-group", @rock_group.slug, @pop_group.slug ],
      snapshot: @snapshot
    )

    lanes = builder.call

    assert_equal [ @rock_group.slug ], lanes.map { |lane| lane.group.slug }
    assert_equal [ rock_event.id ], lanes.first.events.map(&:id)
  end

  test "orders lane events chronologically" do
    normal_earlier = build_lane_event(slug: "lane-normal-earlier", artist_name: "Normal Earlier", start_at: 5.days.from_now.change(hour: 18))
    highlighted_later = build_lane_event(slug: "lane-highlighted-later", artist_name: "Highlighted Later", start_at: 5.days.from_now.change(hour: 22), highlighted: true)
    sks_middle = build_lane_event(slug: "lane-sks-middle", artist_name: "SKS Middle", start_at: 5.days.from_now.change(hour: 20), promoter_id: "10135")
    normal_latest = build_lane_event(slug: "lane-normal-latest", artist_name: "Normal Latest", start_at: 5.days.from_now.change(hour: 23))

    [ normal_earlier, highlighted_later, sks_middle, normal_latest ].each do |event|
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lanes = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day),
      slugs: [ @rock_group.slug ],
      snapshot: @snapshot
    ).call

    assert_equal [
      normal_earlier.id,
      sks_middle.id,
      highlighted_later.id,
      normal_latest.id
    ], lanes.first.events.map(&:id)
  end

  test "uses the snapshot-specific lane configuration by default" do
    rock_event = build_lane_event(slug: "lane-default-rock", artist_name: "Default Rock", start_at: 10.days.from_now.change(hour: 20))
    pop_event = build_lane_event(slug: "lane-default-pop", artist_name: "Default Pop", start_at: 10.days.from_now.change(hour: 21))

    build_lane_enrichment(event: rock_event, genres: [ "Rock" ])
    build_lane_enrichment(event: pop_event, genres: [ "Pop" ])

    lanes = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
    ).call

    assert_equal [ @rock_group.slug, @pop_group.slug ], lanes.map { |lane| lane.group.slug }
  end

  test "uses 15 as the default limit for lane events" do
    105.times do |index|
      event = build_lane_event(
        slug: "lane-limit-#{index}",
        artist_name: "Lane Limit #{index}",
        start_at: (index + 1).days.from_now.change(hour: 20)
      )
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lanes = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day),
      slugs: [ @rock_group.slug ],
      snapshot: @snapshot
    ).call

    assert_equal 15, lanes.first.events.size
    assert_equal "lane-limit-0", lanes.first.events.first.slug
    assert_equal "lane-limit-14", lanes.first.events.last.slug
  end

  test "returns all lane events when limit is nil" do
    18.times do |index|
      event = build_lane_event(
        slug: "lane-unlimited-#{index}",
        artist_name: "Lane Unlimited #{index}",
        start_at: (index + 1).days.from_now.change(hour: 20)
      )
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lanes = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day),
      slugs: [ @rock_group.slug ],
      snapshot: @snapshot,
      limit: nil
    ).call

    assert_equal 18, lanes.first.events.size
    assert_equal "lane-unlimited-0", lanes.first.events.first.slug
    assert_equal "lane-unlimited-17", lanes.first.events.last.slug
  end

  test "deduplicates event series to the next upcoming event per lane" do
    series = EventSeries.create!(origin: "manual", name: "Frida Reihe")
    later_highlighted = build_lane_event(
      slug: "lane-series-later",
      artist_name: "Viva la Vida",
      start_at: 7.days.from_now.change(hour: 22),
      highlighted: true
    )
    earlier_regular = build_lane_event(
      slug: "lane-series-earlier",
      artist_name: "Viva la Vida",
      start_at: 7.days.from_now.change(hour: 18)
    )

    [ later_highlighted, earlier_regular ].each do |event|
      event.update!(event_series: series, event_series_assignment: "manual")
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lanes = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day),
      slugs: [ @rock_group.slug ],
      snapshot: @snapshot
    ).call

    assert_equal [ earlier_regular.id ], lanes.first.events.map(&:id)
    assert_equal [ series.id ], lanes.first.effective_series_ids
  end

  test "marks a lane event as event series when another published event exists only in the past" do
    series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
    future_event = build_lane_event(
      slug: "lane-series-future-only-visible",
      artist_name: "Viva la Vida",
      start_at: 7.days.from_now.change(hour: 18)
    )
    past_event = build_lane_event(
      slug: "lane-series-past-outside-relation",
      artist_name: "Viva la Vida",
      start_at: 2.days.ago.change(hour: 18),
      published_at: 5.days.ago
    )

    [ future_event, past_event ].each do |event|
      event.update!(event_series: series, event_series_assignment: "manual")
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lanes = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day),
      slugs: [ @rock_group.slug ],
      snapshot: @snapshot
    ).call

    assert_equal [ future_event.id ], lanes.first.events.map(&:id)
    assert_equal [ series.id ], lanes.first.effective_series_ids
  end

  private

  def build_lane_event(slug:, artist_name:, start_at:, highlighted: false, promoter_id: nil, published_at: 1.day.ago)
    Event.create!(
      slug: slug,
      source_fingerprint: "test::service::homepage-genre-lanes::#{slug}",
      title: "#{artist_name} Title",
      artist_name: artist_name,
      start_at: start_at,
      venue: "Club Zentral",
      city: "Stuttgart",
      promoter_id: promoter_id,
      highlighted: highlighted,
      status: "published",
      published_at: published_at,
      source_snapshot: {}
    )
  end

  def build_lane_enrichment(event:, genres:)
    EventLlmEnrichment.create!(
      event: event,
      source_run: import_runs(:one),
      genre: genres,
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )
  end
end
