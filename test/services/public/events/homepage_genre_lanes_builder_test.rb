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

  test "prioritizes highlighted events before sks events before the rest" do
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
      highlighted_later.id,
      sks_middle.id,
      normal_earlier.id,
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

  test "uses 100 as the default limit for lane events" do
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

    assert_equal 100, lanes.first.events.size
    assert_equal "lane-limit-0", lanes.first.events.first.slug
    assert_equal "lane-limit-99", lanes.first.events.last.slug
  end

  private

  def build_lane_event(slug:, artist_name:, start_at:, highlighted: false, promoter_id: nil)
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
      published_at: 1.day.ago,
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
