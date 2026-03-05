require "test_helper"

class Editorial::EventsInboxQueryTest < ActiveSupport::TestCase
  setup do
    @created_event = events(:needs_review_one)
    @updated_event = events(:needs_review_two)
    @merge_run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "merge",
      status: "succeeded",
      started_at: Time.zone.parse("2026-03-06 10:00:00"),
      finished_at: Time.zone.parse("2026-03-06 10:05:00")
    )

    @created_event.event_change_logs.create!(
      action: "merged_create",
      user: nil,
      changed_fields: {},
      metadata: { "merge_run_id" => @merge_run.id }
    )
    @updated_event.event_change_logs.create!(
      action: "merged_update",
      user: nil,
      changed_fields: {},
      metadata: { "merge_run_id" => @merge_run.id }
    )
  end

  test "filters last merge created events" do
    result = Editorial::EventsInboxQuery.new(
      params: {
        status: "needs_review",
        merge_scope: "last_merge",
        merge_change_type: "created",
        merge_run_id: @merge_run.id
      }
    ).call

    assert_equal [ @created_event.id ], result.pluck(:id)
  end

  test "filters last merge updated events" do
    result = Editorial::EventsInboxQuery.new(
      params: {
        status: "needs_review",
        merge_scope: "last_merge",
        merge_change_type: "updated",
        merge_run_id: @merge_run.id
      }
    ).call

    assert_equal [ @updated_event.id ], result.pluck(:id)
  end

  test "returns none for last merge filter when merge run id is missing" do
    result = Editorial::EventsInboxQuery.new(
      params: {
        status: "needs_review",
        merge_scope: "last_merge",
        merge_change_type: "all"
      }
    ).call

    assert_equal [], result.pluck(:id)
  end
end
