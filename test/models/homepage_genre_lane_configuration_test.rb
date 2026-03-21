require "test_helper"

class HomepageGenreLaneConfigurationTest < ActiveSupport::TestCase
  test "normalizes lane slugs" do
    snapshot = ImportRun.create!(
      import_source: import_sources(:two),
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 1.minute.ago,
      finished_at: Time.current
    ).create_llm_genre_grouping_snapshot!(
      active: false,
      requested_group_count: 2,
      effective_group_count: 2,
      source_genres_count: 2,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )

    configuration = snapshot.build_homepage_genre_lane_configuration(
      lane_slugs: [ "", "Rock & Alternative", "pop-mainstream", "Rock & Alternative" ]
    )

    assert configuration.valid?
    assert_equal [ "rock-alternative", "pop-mainstream" ], configuration.lane_slugs
  end
end
