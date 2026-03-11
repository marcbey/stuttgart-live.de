require "test_helper"

class Public::Events::BrowseStateTest < ActiveSupport::TestCase
  test "defaults to grid view, sks filter, first page" do
    state = Public::Events::BrowseState.new({})

    assert_equal Public::Events::BrowseState::VIEW_GRID, state.view
    assert_equal Public::Events::BrowseState::FILTER_SKS, state.filter
    assert_equal 1, state.page
    assert_nil state.event_date
    assert_nil state.query
    assert_predicate state, :grid?
  end

  test "list view forces all filter" do
    state = Public::Events::BrowseState.new({ "view" => "list", "filter" => "sks", "page" => "3" })

    assert_equal Public::Events::BrowseState::VIEW_LIST, state.view
    assert_equal Public::Events::BrowseState::FILTER_ALL, state.filter
    assert_equal 3, state.page
    assert_predicate state, :list?
  end

  test "invalid date falls back to nil" do
    state = Public::Events::BrowseState.new({ "event_date" => "not-a-date" })

    assert_nil state.event_date
    assert_nil state.event_date_param
  end

  test "route params normalize list view and pagination" do
    state = Public::Events::BrowseState.new({
      "filter" => "sks",
      "view" => "grid",
      "event_date" => "2026-07-10",
      "q" => "Review Artist"
    })

    assert_equal(
      {
        filter: "all",
        view: "list",
        event_date: "2026-07-10",
        q: "Review Artist",
        page: 2,
        format: :turbo_stream
      },
      state.route_params(page: 2, view: "list", format: :turbo_stream)
    )
  end
end
