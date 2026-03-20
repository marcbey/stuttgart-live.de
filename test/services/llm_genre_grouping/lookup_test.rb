require "test_helper"

class LlmGenreGrouping::LookupTest < ActiveSupport::TestCase
  setup do
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
  end

  test "returns active snapshot" do
    assert_equal @snapshot, LlmGenreGrouping::Lookup.active_snapshot
  end

  test "finds groups for an event by overlapping llm enrichment genres" do
    groups = LlmGenreGrouping::Lookup.groups_for_event(events(:published_one))

    assert_equal [ @rock_group.id ], groups.pluck(:id)
  end

  test "finds events for a group by overlapping member genres" do
    events = LlmGenreGrouping::Lookup.events_for_group(@jazz_group)

    assert_equal [ events(:needs_review_one).id ], events.pluck(:id)
  end
end
