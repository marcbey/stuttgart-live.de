require "test_helper"

class LlmGenreGrouping::LookupTest < ActiveSupport::TestCase
  setup do
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.where(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY).delete_all
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [ "10135" ])
    @run = import_sources(:two).import_runs.create!(
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    @snapshot = @run.create_llm_genre_grouping_snapshot!(
      active: true,
      requested_group_count: 30,
      effective_group_count: 2,
      source_genres_count: 4,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )
    @rock_group = @snapshot.groups.create!(position: 1, name: "Rock & Pop", member_genres: [ "Rock", "Pop" ])
    @jazz_group = @snapshot.groups.create!(position: 2, name: "Jazz", member_genres: [ "Jazz" ])
    AppSetting.create!(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY, value: @snapshot.id)

    EventLlmEnrichment.create!(
      event: events(:published_one),
      source_run: import_runs(:one),
      genre: [ "Rock" ],
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )
    EventLlmEnrichment.create!(
      event: events(:needs_review_one),
      source_run: import_runs(:one),
      genre: [ "Jazz" ],
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )

    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "returns selected snapshot" do
    assert_equal @snapshot, LlmGenreGrouping::Lookup.selected_snapshot
  end

  test "finds groups for an event by overlapping llm enrichment genres" do
    groups = LlmGenreGrouping::Lookup.groups_for_event(events(:published_one))

    assert_equal [ @rock_group.id ], groups.pluck(:id)
  end

  test "finds events for a group by overlapping member genres" do
    events = LlmGenreGrouping::Lookup.events_for_group(@jazz_group)

    assert_equal [ events(:needs_review_one).id ], events.pluck(:id)
  end

  test "orders group events chronologically" do
    normal_earlier = build_group_event(slug: "lookup-normal-earlier", artist_name: "Normal Earlier", start_at: 5.days.from_now.change(hour: 18))
    highlighted_later = build_group_event(slug: "lookup-highlighted-later", artist_name: "Highlighted Later", start_at: 5.days.from_now.change(hour: 22), highlighted: true)
    sks_middle = build_group_event(slug: "lookup-sks-middle", artist_name: "SKS Middle", start_at: 5.days.from_now.change(hour: 20), promoter_id: "10135")
    normal_latest = build_group_event(slug: "lookup-normal-latest", artist_name: "Normal Latest", start_at: 5.days.from_now.change(hour: 23))
    relation = Event.where(id: [ normal_earlier.id, highlighted_later.id, sks_middle.id, normal_latest.id ])

    [ normal_earlier, highlighted_later, sks_middle, normal_latest ].each do |event|
      build_group_enrichment(event:, genres: [ "Rock" ])
    end

    events = LlmGenreGrouping::Lookup.chronological_events_for_group(
      @rock_group,
      relation: relation
    )

    assert_equal [
      normal_earlier.id,
      sks_middle.id,
      highlighted_later.id,
      normal_latest.id
    ], events.map(&:id)
  end

  test "excludes a given event id from chronological group events" do
    excluded_event = build_group_event(slug: "lookup-excluded", artist_name: "Excluded", start_at: 5.days.from_now.change(hour: 18))
    remaining_event = build_group_event(slug: "lookup-remaining", artist_name: "Remaining", start_at: 5.days.from_now.change(hour: 20))
    relation = Event.where(id: [ excluded_event.id, remaining_event.id ])

    [ excluded_event, remaining_event ].each do |event|
      build_group_enrichment(event:, genres: [ "Rock" ])
    end

    events = LlmGenreGrouping::Lookup.chronological_events_for_group(
      @rock_group,
      relation: relation,
      exclude_event_id: excluded_event.id
    )

    assert_equal [ remaining_event.id ], events.map(&:id)
  end

  test "uses 100 as the default limit for chronological group events" do
    event_ids = []

    105.times do |index|
      event = build_group_event(
        slug: "lookup-limit-#{index}",
        artist_name: "Limit #{index}",
        start_at: (index + 1).days.from_now.change(hour: 20)
      )
      event_ids << event.id
      build_group_enrichment(event:, genres: [ "Rock" ])
    end

    events = LlmGenreGrouping::Lookup.chronological_events_for_group(
      @rock_group,
      relation: Event.where(id: event_ids)
    )

    assert_equal 100, events.size
    assert_equal "lookup-limit-0", events.first.slug
    assert_equal "lookup-limit-99", events.last.slug
  end

  private

  def build_group_event(slug:, artist_name:, start_at:, highlighted: false, promoter_id: nil)
    Event.create!(
      slug: slug,
      source_fingerprint: "test::service::lookup::#{slug}",
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

  def build_group_enrichment(event:, genres:)
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
