require "test_helper"

class Meta::Onboarding::InstagramAuthorizationUrlBuilderTest < ActiveSupport::TestCase
  test "builds an instagram oauth url with business scopes" do
    session = {}

    url = Meta::Onboarding::InstagramAuthorizationUrlBuilder.new(app_id: "123456").call(
      session:,
      redirect_uri: "https://example.test/backend/meta_connection/callback"
    )

    uri = URI.parse(url)
    params = Rack::Utils.parse_nested_query(uri.query)

    assert_equal "www.instagram.com", uri.host
    assert_equal "/oauth/authorize", uri.path
    assert_equal "123456", params["client_id"]
    assert_equal "code", params["response_type"]
    assert_equal "false", params["enable_fb_login"]
    assert_equal "true", params["force_reauth"]
    assert_equal Meta::Onboarding::InstagramAuthorizationUrlBuilder::REQUIRED_SCOPES.join(","), params["scope"]
    assert_equal session[Meta::Onboarding::InstagramAuthorizationUrlBuilder::SESSION_KEY], params["state"]
  end
end
