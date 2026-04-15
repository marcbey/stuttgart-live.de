require "test_helper"

class Meta::AccessStatusTest < ActiveSupport::TestCase
  setup do
    @connection = SocialConnection.create!(
      provider: "meta",
      auth_mode: "facebook_login_for_business",
      connection_status: "connected",
      user_access_token: "user-token",
      user_token_expires_at: 30.days.from_now,
      granted_scopes: %w[pages_show_list pages_read_engagement pages_manage_posts instagram_basic instagram_content_publish]
    )
    @page_target = @connection.social_connection_targets.create!(
      target_type: "facebook_page",
      external_id: "page-123",
      name: "Test SL",
      access_token: "page-token",
      selected: true,
      status: "selected"
    )
    @connection.social_connection_targets.create!(
      target_type: "instagram_account",
      external_id: "ig-123",
      username: "sl_test_26",
      parent_target: @page_target,
      selected: true,
      status: "selected"
    )
  end

  test "returns ok when debug token and page linkage are valid" do
    client = StubHttpClient.new(
      "https://graph.facebook.com/v25.0/debug_token" => {
        "data" => {
          "is_valid" => true,
          "expires_at" => 14.days.from_now.to_i,
          "scopes" => %w[pages_show_list pages_read_engagement pages_manage_posts instagram_basic instagram_content_publish]
        }
      },
      "https://graph.facebook.com/v25.0/page-123" => {
        "id" => "page-123",
        "name" => "Test SL",
        "instagram_business_account" => {
          "id" => "ig-123",
          "username" => "sl_test_26"
        }
      }
    )

    status = Meta::AccessStatus.new(
      connection_resolver: StubConnectionResolver.new(@connection),
      health_check: Meta::ConnectionHealthCheck.new(
        http_client: client,
        page_catalog_fetcher: StubPageCatalogFetcher.new([]),
        token_refresher: StubTokenRefresher.new,
        app_id: "app-123",
        app_secret: "secret-123"
      ),
      cache: ActiveSupport::Cache::MemoryStore.new
    ).call

    assert_predicate status, :ok?
    assert_equal "connected", status.connection_status
    assert_equal "Test SL", status.page_name
    assert_equal "sl_test_26", status.instagram_username
    assert_equal %w[pages_show_list pages_read_engagement pages_manage_posts instagram_basic instagram_content_publish], status.permissions
    assert status.expires_at.present?
  end

  test "returns warning when token expires soon" do
    client = StubHttpClient.new(
      "https://graph.facebook.com/v25.0/debug_token" => {
        "data" => {
          "is_valid" => true,
          "expires_at" => 3.days.from_now.to_i,
          "scopes" => %w[pages_show_list pages_read_engagement pages_manage_posts instagram_basic instagram_content_publish]
        }
      },
      "https://graph.facebook.com/v25.0/page-123" => {
        "id" => "page-123",
        "name" => "Test SL",
        "instagram_business_account" => {
          "id" => "ig-123",
          "username" => "sl_test_26"
        }
      }
    )

    status = Meta::AccessStatus.new(
      connection_resolver: StubConnectionResolver.new(@connection),
      health_check: Meta::ConnectionHealthCheck.new(
        http_client: client,
        page_catalog_fetcher: StubPageCatalogFetcher.new([]),
        token_refresher: StubTokenRefresher.new,
        app_id: "app-123",
        app_secret: "secret-123"
      ),
      cache: ActiveSupport::Cache::MemoryStore.new
    ).call

    assert_predicate status, :warning?
    assert_equal "expiring_soon", status.connection_status
    assert_match(/läuft bald ab/, status.summary)
    assert status.expires_at.present?
  end

  test "returns error when token debug says the token is invalid" do
    client = StubHttpClient.new(
      "https://graph.facebook.com/v25.0/debug_token" => {
        "data" => {
          "is_valid" => false
        }
      }
    )

    status = Meta::AccessStatus.new(
      connection_resolver: StubConnectionResolver.new(@connection),
      health_check: Meta::ConnectionHealthCheck.new(
        http_client: client,
        page_catalog_fetcher: StubPageCatalogFetcher.new([]),
        token_refresher: StubTokenRefresher.new,
        app_id: "app-123",
        app_secret: "secret-123"
      ),
      cache: ActiveSupport::Cache::MemoryStore.new
    ).call

    assert_predicate status, :error?
    assert_equal "reauth_required", status.connection_status
    assert_equal "Meta-Token ist abgelaufen oder ungültig.", status.summary
  end

  test "returns warning when selected facebook page has no linked instagram account" do
    @connection.selected_instagram_target.destroy!

    client = StubHttpClient.new(
      "https://graph.facebook.com/v25.0/debug_token" => {
        "data" => {
          "is_valid" => true,
          "expires_at" => 14.days.from_now.to_i,
          "scopes" => %w[pages_show_list pages_read_engagement pages_manage_posts instagram_basic instagram_content_publish]
        }
      },
      "https://graph.facebook.com/v25.0/page-123" => {
        "id" => "page-123",
        "name" => "Test SL"
      }
    )

    status = Meta::AccessStatus.new(
      connection_resolver: StubConnectionResolver.new(@connection),
      health_check: Meta::ConnectionHealthCheck.new(
        http_client: client,
        page_catalog_fetcher: StubPageCatalogFetcher.new([]),
        token_refresher: StubTokenRefresher.new,
        app_id: "app-123",
        app_secret: "secret-123"
      ),
      cache: ActiveSupport::Cache::MemoryStore.new
    ).call

    assert_predicate status, :warning?
    assert_equal "connected", status.connection_status
    assert_match(/kein Instagram-Professional-Account/, status.summary)
  end

  private

  class StubConnectionResolver
    def initialize(connection)
      @connection = connection
    end

    def connection
      @connection
    end
  end

  class StubHttpClient
    def initialize(responses)
      @responses = responses
    end

    def get_json!(url, params: {})
      @responses.fetch(url)
    end
  end

  class StubTokenRefresher
    def call(token:)
      Struct.new(:access_token, :expires_at).new(token, 60.days.from_now)
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
