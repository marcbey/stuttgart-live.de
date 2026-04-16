require "test_helper"

class Meta::Onboarding::InstagramCallbackHandlerTest < ActiveSupport::TestCase
  test "persists the instagram login connection and selected instagram target" do
    session = { Meta::Onboarding::InstagramAuthorizationUrlBuilder::SESSION_KEY => "valid-state" }

    handler = Meta::Onboarding::InstagramCallbackHandler.new(
      http_client: StubHttpClient.new,
      token_refresher: StubTokenRefresher.new,
      instagram_account_fetcher: StubInstagramAccountFetcher.new,
      app_id: "app-123",
      app_secret: "secret-123"
    )

    connection = handler.call(
      code: "valid-code",
      state: "valid-state",
      session:,
      redirect_uri: "https://example.test/backend/meta_connection/callback"
    )

    assert_predicate connection, :persisted?
    assert_equal "meta", connection.provider
    assert_equal "instagram_login", connection.auth_mode
    assert_equal "app-scoped-user-123", connection.external_user_id
    assert_equal "long-lived-token", connection.user_access_token
    assert_equal "connected", connection.connection_status
    assert_equal %w[instagram_business_basic instagram_business_content_publish], connection.granted_scopes
    assert_equal "ig-prof-123", connection.metadata["instagram_user_id"]
    assert_equal "stuttgart.live", connection.metadata["instagram_username"]

    instagram_targets = connection.social_connection_targets.instagram_accounts.order(:external_id)

    assert_equal [ "ig-prof-123" ], instagram_targets.map(&:external_id)
    assert_equal "stuttgart.live", instagram_targets.first.username
    assert_predicate instagram_targets.first, :selected?
    assert_nil session[Meta::Onboarding::InstagramAuthorizationUrlBuilder::SESSION_KEY]
  end

  private

  class StubHttpClient
    def post_form!(url, params:)
      case url
      when "https://api.instagram.com/oauth/access_token"
        {
          "access_token" => "short-lived-token",
          "expires_in" => 3600,
          "permissions" => %w[instagram_business_basic instagram_business_content_publish]
        }
      else
        raise "Unexpected URL: #{url}"
      end
    end
  end

  class StubTokenRefresher
    def call(token:, auth_mode:)
      raise "Unexpected auth mode: #{auth_mode}" unless auth_mode == "instagram_login"

      Struct.new(:access_token, :expires_at).new("long-lived-token", 60.days.from_now)
    end
  end

  class StubInstagramAccountFetcher
    def call(user_access_token:)
      raise "Unexpected token: #{user_access_token}" unless user_access_token == "long-lived-token"

      {
        "id" => "app-scoped-user-123",
        "user_id" => "ig-prof-123",
        "username" => "stuttgart.live",
        "account_type" => "BUSINESS",
        "name" => "Stuttgart Live"
      }
    end
  end
end
