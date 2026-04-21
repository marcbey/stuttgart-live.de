require "test_helper"

class Meta::Onboarding::CallbackHandlerTest < ActiveSupport::TestCase
  test "persists the meta connection, keeps instagram selected and requires page selection when multiple pages match" do
    session = { Meta::Onboarding::AuthorizationUrlBuilder::SESSION_KEY => "valid-state" }
    page_accounts = [
      Meta::PageCatalogFetcher::PageAccount.new(
        page_id: "page-1",
        page_name: "Stuttgart Live",
        page_access_token: "page-token-1",
        instagram_account_id: "ig-1",
        instagram_username: "stuttgart.live"
      ),
      Meta::PageCatalogFetcher::PageAccount.new(
        page_id: "page-2",
        page_name: "Stuttgart Live Backup",
        page_access_token: "page-token-2",
        instagram_account_id: "ig-1",
        instagram_username: "stuttgart.live"
      )
    ]

    handler = Meta::Onboarding::CallbackHandler.new(
      http_client: StubHttpClient.new,
      token_refresher: StubTokenRefresher.new,
      page_catalog_fetcher: StubPageCatalogFetcher.new(page_accounts),
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
    assert_equal "facebook_login_for_business", connection.auth_mode
    assert_equal "user-123", connection.external_user_id
    assert_equal "long-lived-token", connection.user_access_token
    assert_equal "pending_selection", connection.connection_status
    assert_equal %w[instagram_basic instagram_content_publish pages_manage_posts pages_read_engagement pages_show_list],
      connection.granted_scopes

    facebook_targets = connection.social_connection_targets.facebook_pages.order(:external_id)
    instagram_targets = connection.social_connection_targets.instagram_accounts.order(:external_id)

    assert_equal %w[page-1 page-2], facebook_targets.map(&:external_id)
    assert_equal [ "ig-1" ], instagram_targets.map(&:external_id)
    assert_equal "Stuttgart Live", facebook_targets.first.name
    assert_equal "stuttgart.live", instagram_targets.first.username
    assert_nil connection.selected_facebook_page_target
    assert_equal "ig-1", connection.selected_instagram_target.external_id
    assert_nil session[Meta::Onboarding::AuthorizationUrlBuilder::SESSION_KEY]
  end

  test "auto-selects the only facebook page that is linked to an instagram professional account" do
    session = { Meta::Onboarding::AuthorizationUrlBuilder::SESSION_KEY => "valid-state" }
    page_accounts = [
      Meta::PageCatalogFetcher::PageAccount.new(
        page_id: "page-1",
        page_name: "Stuttgart Live",
        page_access_token: "page-token-1",
        instagram_account_id: "ig-1",
        instagram_username: "stuttgart.live"
      ),
      Meta::PageCatalogFetcher::PageAccount.new(
        page_id: "page-2",
        page_name: "Stuttgart Live Backup",
        page_access_token: "page-token-2",
        instagram_account_id: nil,
        instagram_username: nil
      )
    ]

    handler = Meta::Onboarding::CallbackHandler.new(
      http_client: StubHttpClient.new("page-1"),
      token_refresher: StubTokenRefresher.new,
      page_catalog_fetcher: StubPageCatalogFetcher.new(page_accounts),
      app_id: "app-123",
      app_secret: "secret-123"
    )

    connection = handler.call(
      code: "valid-code",
      state: "valid-state",
      session:,
      redirect_uri: "https://example.test/backend/meta_connection/callback"
    )

    assert_equal "connected", connection.connection_status
    assert_equal "page-1", connection.selected_facebook_page_target.external_id
    assert_equal "ig-1", connection.selected_instagram_target.external_id
  end

  private

  class StubHttpClient
    def initialize(selected_page_id = nil)
      @selected_page_id = selected_page_id
    end

    def get_json!(url, params: {})
      case url
      when "https://graph.facebook.com/v25.0/oauth/access_token"
        { "access_token" => "short-lived-token", "expires_in" => 3600 }
      when "https://graph.facebook.com/v25.0/me"
        { "id" => "user-123", "name" => "Meta User" }
      when "https://graph.facebook.com/v25.0/me/permissions"
        {
          "data" => [
            { "permission" => "pages_show_list", "status" => "granted" },
            { "permission" => "pages_read_engagement", "status" => "granted" },
            { "permission" => "pages_manage_posts", "status" => "granted" },
            { "permission" => "instagram_basic", "status" => "granted" },
            { "permission" => "instagram_content_publish", "status" => "granted" }
          ]
        }
      when "https://graph.facebook.com/v25.0/#{@selected_page_id}"
        {
          "id" => @selected_page_id,
          "name" => "Stuttgart Live",
          "instagram_business_account" => {
            "id" => "ig-1",
            "username" => "stuttgart.live"
          }
        }
      else
        raise "Unexpected URL: #{url}"
      end
    end
  end

  class StubTokenRefresher
    def call(token:, auth_mode: nil)
      Struct.new(:access_token, :expires_at).new("long-lived-token", 60.days.from_now)
    end
  end

  class StubPageCatalogFetcher
    def initialize(page_accounts)
      @page_accounts = page_accounts
    end

    def call(user_access_token:)
      @page_accounts
    end
  end
end
