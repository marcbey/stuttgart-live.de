require "test_helper"

class Public::Events::HomepageGenreLanesBuilderTest < ActiveSupport::TestCase
  setup do
    EventGenre.delete_all
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.where(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY).delete_all
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [ "10135" ])
    @rock_group = genres(:rock)
    @pop_group = genres(:pop)
    AppSetting.create!(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY, value: [ @rock_group.slug, @pop_group.slug ])
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "builds lanes in configured order and ignores unknown or empty groups" do
    rock_event = build_lane_event(slug: "lane-rock", artist_name: "Rock Event", start_at: 10.days.from_now.change(hour: 20))
    build_lane_enrichment(event: rock_event, genres: [ "Rock" ])

    builder = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day),
      slugs: [ "missing-group", @rock_group.slug, @pop_group.slug ]
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
      slugs: [ @rock_group.slug ]
    ).call

    assert_equal [
      normal_earlier.id,
      sks_middle.id,
      highlighted_later.id,
      normal_latest.id
    ], lanes.first.events.map(&:id)
  end

  test "uses the configured lane slugs by default" do
    rock_event = build_lane_event(slug: "lane-default-rock", artist_name: "Default Rock", start_at: 10.days.from_now.change(hour: 20))
    pop_event = build_lane_event(slug: "lane-default-pop", artist_name: "Default Pop", start_at: 10.days.from_now.change(hour: 21))

    build_lane_enrichment(event: rock_event, genres: [ "Rock" ])
    build_lane_enrichment(event: pop_event, genres: [ "Pop" ])

    lanes = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
    ).call

    assert_equal [ @rock_group.slug, @pop_group.slug ], lanes.map { |lane| lane.group.slug }
  end

  test "uses 10 as the default limit for lane events" do
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
      slugs: [ @rock_group.slug ]
    ).call

    assert_equal 10, lanes.first.events.size
    assert_equal "lane-limit-0", lanes.first.events.first.slug
    assert_equal "lane-limit-9", lanes.first.events.last.slug
    assert_predicate lanes.first.next_cursor, :present?
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
      limit: nil
    ).call

    assert_equal 18, lanes.first.events.size
    assert_equal "lane-unlimited-0", lanes.first.events.first.slug
    assert_equal "lane-unlimited-17", lanes.first.events.last.slug
  end

  test "uses a bounded candidate limit for homepage lanes" do
    event = build_lane_event(
      slug: "lane-candidate-limit",
      artist_name: "Lane Candidate Limit",
      start_at: 3.days.from_now.change(hour: 20)
    )
    build_lane_enrichment(event: event, genres: [ "Rock" ])

    lanes = Public::Events::HomepageGenreLanesBuilder.new(
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day),
      slugs: [ @rock_group.slug ]
    ).call

    assert_equal [ event.id ], lanes.first.events.map(&:id)
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
      slugs: [ @rock_group.slug ]
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
      slugs: [ @rock_group.slug ]
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
    event.genres = genres.map { |name| genre_for(name) }
  end

  def genre_for(name)
    case name
    when "Rock"
      @rock_group
    when "Pop"
      @pop_group
    else
      Genre.find_by!(name: name)
    end
  end
end
