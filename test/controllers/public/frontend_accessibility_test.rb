require "test_helper"

class Public::FrontendAccessibilityTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    StaticPageDefaults.ensure!
  end

  teardown { travel_back }

  test "public page families expose one top level main landmark" do
    [ root_path, highlights_lane_path, genre_lane_path("rock-alternative"), saved_events_path,
      search_path(q: "Unfindbarer Konzertabend"), news_index_path, contact_path ].each do |path|
      get path

      assert_response :success
      assert_select "main", count: 1, message: "Expected one main landmark on #{path}"
      assert_select "main main", count: 0
    end
  end

  test "event lists and saved events have a primary heading" do
    [ highlights_lane_path, all_stuttgart_lane_path, genre_lane_path("rock-alternative"), saved_events_path ].each do |path|
      get path

      assert_response :success
      assert_select "h1", count: 1, message: "Expected a page heading on #{path}"
    end
  end

  test "stored service headings do not introduce a second page title" do
    StaticPage.find_by!(slug: "faq").update!(body: "<h1>Fragen zu deinem Besuch</h1><p>Informationen für deinen Konzertabend.</p>")

    get faq_path

    assert_response :success
    assert_select "h1", count: 1
    assert_select "h2", text: "Fragen zu deinem Besuch"
    assert_select "p", text: "Informationen für deinen Konzertabend."
  end

  test "event description disclosure uses a keyboard focusable button" do
    get event_path(events(:published_one).slug)

    assert_response :success
    assert_select "button[type='button'][aria-controls='design-detail-preview-description-body'][aria-expanded='false']", count: 1
    assert_select "label[aria-expanded]", count: 0
  end
end
