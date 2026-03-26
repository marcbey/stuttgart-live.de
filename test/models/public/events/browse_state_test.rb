require "test_helper"

class Public::Events::BrowseStateTest < ActiveSupport::TestCase
  test "defaults to sks filter and first page" do
    state = Public::Events::BrowseState.new({})

    assert_equal Public::Events::BrowseState::FILTER_SKS, state.filter
    assert_equal 1, state.page
    assert_nil state.event_date
    assert_nil state.query
  end

  test "keeps explicit filter and ignores deprecated view param" do
    state = Public::Events::BrowseState.new({ "view" => "list", "filter" => "all", "page" => "3" })

    assert_equal Public::Events::BrowseState::FILTER_ALL, state.filter
    assert_equal 3, state.page
  end

  test "invalid date falls back to nil" do
    state = Public::Events::BrowseState.new({ "event_date" => "not-a-date" })

    assert_nil state.event_date
    assert_nil state.event_date_param
  end

  test "route params preserve pagination and format" do
    state = Public::Events::BrowseState.new({
      "filter" => "sks",
      "view" => "grid",
      "event_date" => "2026-07-10",
      "q" => "Review Artist"
    })

    assert_equal(
      {
        event_date: "2026-07-10",
        q: "Review Artist",
        page: 2,
        format: :turbo_stream
      },
      state.route_params(page: 2, format: :turbo_stream)
    )
  end

  test "punctuation only query is not treated as a search query" do
    state = Public::Events::BrowseState.new({ "q" => " ... !!! " })

    assert_equal "... !!!", state.query
    assert_nil state.normalized_query
    assert_not state.search_query_present?
    assert_equal({}, state.route_params)
  end
end
