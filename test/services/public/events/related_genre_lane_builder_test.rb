require "test_helper"

class Public::Events::RelatedGenreLaneBuilderTest < ActiveSupport::TestCase
  setup do
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.where(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY).delete_all
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
      source_genres_count: 3,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )

    @rock_group = @snapshot.groups.create!(position: 1, name: "Rock & Alternative", member_genres: [ "Rock" ])
    @pop_group = @snapshot.groups.create!(position: 2, name: "Pop & Mainstream", member_genres: [ "Pop" ])
    AppSetting.create!(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY, value: @snapshot.id)
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "builds a lane for the first matching group and excludes the current event" do
    current_event = build_lane_event(slug: "related-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    matching_event = build_lane_event(slug: "related-match", artist_name: "Matching Event", start_at: 5.days.from_now.change(hour: 20))

    build_lane_enrichment(event: current_event, genres: [ "Rock", "Pop" ])
    build_lane_enrichment(event: matching_event, genres: [ "Rock" ])

    lane = build_builder(event: current_event).call

    assert_equal @rock_group.id, lane.group.id
    assert_equal [ matching_event.id ], lane.events.map(&:id)
  end

  test "returns nil when no other matching events remain after excluding the current event" do
    current_event = build_lane_event(slug: "related-only-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    build_lane_enrichment(event: current_event, genres: [ "Rock" ])

    assert_nil build_builder(event: current_event).call
  end

  test "ignores unpublished and past matching events" do
    current_event = build_lane_event(slug: "related-filter-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    published_future = build_lane_event(slug: "related-filter-published", artist_name: "Published Future", start_at: 5.days.from_now.change(hour: 20))
    unpublished_future = build_lane_event(slug: "related-filter-unpublished", artist_name: "Unpublished Future", start_at: 5.days.from_now.change(hour: 21), status: "needs_review", published_at: nil)
    past_published = build_lane_event(slug: "related-filter-past", artist_name: "Past Published", start_at: 2.days.ago.change(hour: 20), published_at: 5.days.ago)

    [ current_event, published_future, unpublished_future, past_published ].each do |event|
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lane = build_builder(event: current_event).call

    assert_equal [ published_future.id ], lane.events.map(&:id)
  end

  test "orders related lane events chronologically" do
    current_event = build_lane_event(slug: "related-priority-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    normal_earlier = build_lane_event(slug: "related-priority-normal-earlier", artist_name: "Normal Earlier", start_at: 5.days.from_now.change(hour: 18))
    highlighted_later = build_lane_event(slug: "related-priority-highlighted", artist_name: "Highlighted Later", start_at: 5.days.from_now.change(hour: 22), highlighted: true)
    sks_middle = build_lane_event(slug: "related-priority-sks", artist_name: "SKS Middle", start_at: 5.days.from_now.change(hour: 20), promoter_id: "10135")
    normal_latest = build_lane_event(slug: "related-priority-normal-latest", artist_name: "Normal Latest", start_at: 5.days.from_now.change(hour: 23))

    [ current_event, normal_earlier, highlighted_later, sks_middle, normal_latest ].each do |event|
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lane = build_builder(event: current_event).call

    assert_equal [
      normal_earlier.id,
      sks_middle.id,
      highlighted_later.id,
      normal_latest.id
    ], lane.events.map(&:id)
  end

  test "uses 100 as the default limit for related lane events" do
    current_event = build_lane_event(slug: "related-limit-current", artist_name: "Current Event", start_at: 2.days.from_now.change(hour: 20))
    build_lane_enrichment(event: current_event, genres: [ "Rock" ])

    105.times do |index|
      event = build_lane_event(
        slug: "related-limit-#{index}",
        artist_name: "Related Limit #{index}",
        start_at: (index + 3).days.from_now.change(hour: 20)
      )
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lane = build_builder(event: current_event).call

    assert_equal 100, lane.events.size
    assert_equal "related-limit-0", lane.events.first.slug
    assert_equal "related-limit-99", lane.events.last.slug
    assert_not_includes lane.events.map(&:id), current_event.id
  end

  test "marks a related lane event as event series when another published event exists only in the past" do
    series = EventSeries.create!(origin: "manual", name: "Viva la Vida")
    current_event = build_lane_event(slug: "related-series-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    related_future = build_lane_event(slug: "related-series-future", artist_name: "Viva la Vida", start_at: 5.days.from_now.change(hour: 20))
    related_past = build_lane_event(
      slug: "related-series-past",
      artist_name: "Viva la Vida",
      start_at: 2.days.ago.change(hour: 20),
      published_at: 5.days.ago
    )

    build_lane_enrichment(event: current_event, genres: [ "Rock" ])
    [ related_future, related_past ].each do |event|
      event.update!(event_series: series, event_series_assignment: "manual")
      build_lane_enrichment(event: event, genres: [ "Rock" ])
    end

    lane = build_builder(event: current_event).call

    assert_equal [ related_future.id ], lane.events.map(&:id)
    assert_equal [ series.id ], lane.effective_series_ids
  end

  private

  def build_builder(event:)
    Public::Events::RelatedGenreLaneBuilder.new(
      event: event,
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
    )
  end

  def build_lane_event(slug:, artist_name:, start_at:, highlighted: false, promoter_id: nil, status: "published", published_at: 1.day.ago)
    Event.create!(
      slug: slug,
      source_fingerprint: "test::service::related-genre-lane::#{slug}",
      title: "#{artist_name} Title",
      artist_name: artist_name,
      start_at: start_at,
      venue: "Club Zentral",
      city: "Stuttgart",
      promoter_id: promoter_id,
      highlighted: highlighted,
      status: status,
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
