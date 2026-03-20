require "test_helper"

class LlmGenreGroupingSnapshotTest < ActiveSupport::TestCase
  test "generates snapshot key and validates active uniqueness" do
    first = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 1.minute.ago,
      finished_at: Time.current
    ).create_llm_genre_grouping_snapshot!(
      active: true,
      requested_group_count: 30,
      effective_group_count: 30,
      source_genres_count: 120,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )

    assert first.snapshot_key.present?

    second = ImportRun.create!(
      import_source: import_sources(:two),
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 1.minute.ago,
      finished_at: Time.current
    ).build_llm_genre_grouping_snapshot(
      active: true,
      requested_group_count: 20,
      effective_group_count: 20,
      source_genres_count: 80,
      model: "gpt-5-mini",
      prompt_template_digest: "digest-2",
      request_payload: {},
      raw_response: {}
    )

    assert_not second.valid?
    assert_includes second.errors[:active], "has already been taken"
  end
end
