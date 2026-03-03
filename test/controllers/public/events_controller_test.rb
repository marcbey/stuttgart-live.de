require "test_helper"

class Public::EventsControllerTest < ActionDispatch::IntegrationTest
  test "index is publicly accessible" do
    get events_url

    assert_response :success
    assert_includes response.body, "Published Artist"
    assert_not_includes response.body, "Review Artist"
  end

  test "show renders published event by slug" do
    get event_url(events(:published_one).slug)

    assert_response :success
    assert_includes response.body, "Published Artist"
  end

  test "show returns not found for unpublished events" do
    get event_url(events(:needs_review_one).slug)

    assert_response :not_found
  end
end
