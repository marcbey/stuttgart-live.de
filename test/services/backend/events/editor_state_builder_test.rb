require "test_helper"

class Backend::Events::EditorStateBuilderTest < ActiveSupport::TestCase
  setup do
    @status_filters = Event::STATUSES.reject { |status| status == "imported" }
    @session = {}
    @event = events(:needs_review_one)
    @next_event = events(:needs_review_two)
  end

  test "build selects next filtered event when auto-next is enabled" do
    inbox_state = Backend::Events::InboxState.new(
      params: { "query" => "Review Event", "status" => "needs_review" },
      session: @session,
      status_filters: @status_filters
    )
    inbox_state.persist_filters!

    builder = Backend::Events::EditorStateBuilder.new(
      inbox_state: inbox_state,
      latest_successful_merge_run: nil,
      next_event_enabled: true
    )

    result = builder.build(preferred_event: @event, navigation_status: "needs_review")

    assert_equal "needs_review", result.target_status
    assert_equal @next_event.id, result.target_event.id
  end

  test "selected merge run id is returned for last merge scope" do
    merge_run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "merge",
      status: "succeeded",
      started_at: Time.zone.parse("2026-03-06 10:00:00"),
      finished_at: Time.zone.parse("2026-03-06 10:05:00")
    )
    inbox_state = Backend::Events::InboxState.new(
      params: {
        "status" => "needs_review",
        "merge_scope" => "last_merge",
        "merge_change_type" => "updated"
      },
      session: @session,
      status_filters: @status_filters
    )
    inbox_state.persist_filters!

    builder = Backend::Events::EditorStateBuilder.new(
      inbox_state: inbox_state,
      latest_successful_merge_run: merge_run,
      next_event_enabled: false
    )

    assert_equal merge_run.id, builder.selected_merge_run_id_for_status("needs_review")
  end
end
