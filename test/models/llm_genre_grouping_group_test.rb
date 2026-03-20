require "test_helper"

class LlmGenreGroupingGroupTest < ActiveSupport::TestCase
  test "normalizes name slug and member genres" do
    run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 1.minute.ago,
      finished_at: Time.current
    )
    snapshot = run.create_llm_genre_grouping_snapshot!(
      active: true,
      requested_group_count: 30,
      effective_group_count: 30,
      source_genres_count: 120,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )

    group = snapshot.groups.create!(
      position: 1,
      name: " Rock & Pop ",
      member_genres: [ " Rock ", "", "Pop", "Rock" ]
    )

    assert_equal "Rock & Pop", group.name
    assert_equal "rock-pop", group.slug
    assert_equal [ "Pop", "Rock" ], group.member_genres
    assert_equal 2, group.genre_count
  end
end
