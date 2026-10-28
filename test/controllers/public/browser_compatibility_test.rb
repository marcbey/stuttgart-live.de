require "test_helper"

class Public::BrowserCompatibilityTest < ActionDispatch::IntegrationTest
  IPHONE_8_SAFARI = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1".freeze

  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
  end

  test "iPhone 8 Safari can view the homepage" do
    get root_url, headers: { "User-Agent" => IPHONE_8_SAFARI }

    assert_response :success
    assert_includes response.body, "Published Artist"
    assert_select "a[href=?]", event_path(events(:published_one).slug)
  end

  test "iPhone 8 Safari can view event details and ticket links" do
    get event_url(events(:published_one).slug), headers: { "User-Agent" => IPHONE_8_SAFARI }

    assert_response :success
    assert_select "h1", text: /Published Artist/
    assert_select "a[href=?]", event_offers(:published_one_offer).ticket_url
  end

  test "iPhone 8 Safari can view news contact and newsletter pages" do
    StaticPageDefaults.ensure!

    [ news_index_url, contact_url, new_newsletter_subscriber_url ].each do |url|
      get url, headers: { "User-Agent" => IPHONE_8_SAFARI }

      assert_response :success
      assert_select "main"
    end
  end

  test "older iOS Safari can still view the homepage" do
    get root_url, headers: {
      "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1"
    }

    assert_response :success
    assert_includes response.body, "Published Artist"
  end

  test "older Chrome can still view the homepage" do
    get root_url, headers: {
      "User-Agent" => "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36"
    }

    assert_response :success
    assert_includes response.body, "Published Artist"
  end

  test "backoffice and login retain their modern browser requirement" do
    get new_session_url, headers: { "User-Agent" => IPHONE_8_SAFARI }

    assert_response :not_acceptable

    sign_in_as(users(:one))
    get backend_root_url, headers: { "User-Agent" => IPHONE_8_SAFARI }

    assert_response :not_acceptable
  end
end
