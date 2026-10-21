require "test_helper"

class Public::AssetLoadingTest < ActionDispatch::IntegrationTest
  setup do
    StaticPageDefaults.ensure!
  end

  test "public pages load their base and surface styles through one stylesheet" do
    [ root_path, highlights_lane_path, search_path(q: "Rock"), faq_path, news_index_path, "/errors/404", "/errors/500" ].each do |path|
      get path

      assert_response(path.start_with?("/errors/") ? path.delete_prefix("/errors/").to_i : :success, path)
      assert_select "link[rel='stylesheet']", count: 1
      assert_select "link[rel='stylesheet'][href*='/frontend']", count: 1
    end
  end

  test "newsletter forms also load a single public stylesheet" do
    post newsletter_subscribers_path, params: {
      signup_step: "details", source: "footer",
      newsletter_subscriber: { email: "asset-loading@example.com" }
    }

    assert_response :success
    assert_select "link[rel='stylesheet']", count: 1
    assert_select "link[rel='stylesheet'][href*='/frontend']", count: 1
  end

  test "login retains separate shared and backend styles" do
    get new_session_path

    assert_response :success
    assert_select "link[rel='stylesheet']", count: 2
    assert_select "link[rel='stylesheet'][href*='/shared']", count: 1
    assert_select "link[rel='stylesheet'][href*='/backend']", count: 1
    assert_select "link[rel='stylesheet'][href*='/frontend']", count: 0
  end
end
