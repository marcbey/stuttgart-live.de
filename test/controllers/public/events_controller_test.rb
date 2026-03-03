require "test_helper"

class Public::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @published_event = events(:published_one)
    @user = users(:one)
  end

  test "index is publicly accessible" do
    get events_url

    assert_response :success
    assert_includes response.body, "Published Artist"
    assert_not_includes response.body, "Review Artist"
    assert_not_includes response.body, "event-card-status-select"
  end

  test "show renders published event by slug" do
    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, "Published Artist"
  end

  test "show returns not found for unpublished events" do
    get event_url(events(:needs_review_one).slug)

    assert_response :not_found
  end

  test "index shows status overlay for authenticated users" do
    sign_in_as(@user)

    get events_url

    assert_response :success
    assert_includes response.body, "event-card-status-select"
    assert_includes response.body, status_event_path(@published_event.slug)
  end

  test "status update requires authentication" do
    patch status_event_url(@published_event.slug), params: { status: "needs_review" }

    assert_redirected_to new_session_url
  end

  test "authenticated user can update event status from public cards" do
    sign_in_as(@user)

    patch status_event_url(@published_event.slug), params: { status: "needs_review", page: "1" }

    assert_redirected_to events_url(page: "1")
    assert_equal "needs_review", @published_event.reload.status
    assert_nil @published_event.published_at
    assert_nil @published_event.published_by_id
  end

  test "turbo status update removes event card when event becomes unpublished" do
    sign_in_as(@user)

    patch status_event_url(@published_event.slug),
      params: { status: "needs_review", card_slot: "grid_default" },
      as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "action=\"remove\""
    assert_includes response.body, "target=\"card_event_#{@published_event.id}\""
  end
end
