require "test_helper"

class Backend::Events::InboxStateTest < ActiveSupport::TestCase
  setup do
    @status_filters = Event::STATUSES.reject { |status| status == "imported" }
    @available_merge_run_ids = [ 5, 19 ]
  end

  test "defaults to published status and todays starts_after" do
    state = Backend::Events::InboxState.new(
      params: {},
      session: {},
      status_filters: @status_filters,
      available_merge_run_ids: @available_merge_run_ids,
      latest_successful_merge_run_id: 19
    )

    assert_equal "published", state.current_status
    assert_equal Date.current.iso8601, state.filters[:starts_after]
    assert_equal "all", state.filters[:merge_run_id]
    assert_equal "all", state.filters[:merge_change_type]
  end

  test "persists current status from params into session" do
    session = {}
    state = Backend::Events::InboxState.new(
      params: { "status" => "needs_review" },
      session: session,
      status_filters: @status_filters,
      available_merge_run_ids: @available_merge_run_ids,
      latest_successful_merge_run_id: 19
    )

    assert_equal "needs_review", state.current_status
    assert_equal "needs_review", session["backend_events_inbox_status"]
  end

  test "persists normalized filters to session" do
    session = {}
    state = Backend::Events::InboxState.new(
      params: {
        "query" => " Review Artist ",
        "promoter_id" => " 36 ",
        "starts_after" => "2026-07-01",
        "starts_before" => "2026-07-31",
        "merge_run_id" => "19",
        "merge_change_type" => "updated"
      },
      session: session,
      status_filters: @status_filters,
      available_merge_run_ids: @available_merge_run_ids,
      latest_successful_merge_run_id: 19
    )

    state.persist_filters!

    assert_equal(
      {
        "query" => "Review Artist",
        "promoter_id" => "36",
        "starts_after" => "2026-07-01",
        "starts_before" => "2026-07-31",
        "merge_run_id" => "19",
        "merge_change_type" => "updated"
      },
      session["backend_events_inbox_filters"]
    )
  end

  test "normalizes unknown merge run ids to all and resets merge change type" do
    session = {}
    state = Backend::Events::InboxState.new(
      params: {
        "merge_run_id" => "999",
        "merge_change_type" => "updated"
      },
      session: session,
      status_filters: @status_filters,
      available_merge_run_ids: @available_merge_run_ids,
      latest_successful_merge_run_id: 19
    )

    state.persist_filters!

    assert_equal(
      {
        "query" => nil,
        "promoter_id" => nil,
        "starts_after" => nil,
        "starts_before" => nil,
        "merge_run_id" => "all",
        "merge_change_type" => "all"
      },
      session["backend_events_inbox_filters"]
    )
  end

  test "maps legacy last_merge session filter to latest successful merge run" do
    session = {
      "backend_events_inbox_filters" => {
        "merge_scope" => "last_merge",
        "merge_change_type" => "updated"
      }
    }
    state = Backend::Events::InboxState.new(
      params: {},
      session: session,
      status_filters: @status_filters,
      available_merge_run_ids: @available_merge_run_ids,
      latest_successful_merge_run_id: 19
    )

    assert_equal "19", state.filters[:merge_run_id]
    assert_equal "updated", state.filters[:merge_change_type]
  end

  test "clear filters removes stored session filters" do
    session = {
      "backend_events_inbox_filters" => { "query" => "Review Artist" }
    }
    state = Backend::Events::InboxState.new(
      params: { "clear_filters" => "1" },
      session: session,
      status_filters: @status_filters,
      available_merge_run_ids: @available_merge_run_ids,
      latest_successful_merge_run_id: 19
    )

    state.persist_filters!

    assert_nil session["backend_events_inbox_filters"]
  end

  test "next event preference defaults to false and persists boolean values" do
    session = {}
    state = Backend::Events::InboxState.new(
      params: {},
      session: session,
      status_filters: @status_filters,
      available_merge_run_ids: @available_merge_run_ids,
      latest_successful_merge_run_id: 19
    )

    assert_equal false, state.next_event_enabled
    assert_equal true, state.persist_next_event_preference!("1")
    assert_equal true, session["backend_events_next_event_enabled"]
  end
end
