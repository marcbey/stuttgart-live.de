require "test_helper"

class Meta::ConnectionHealthCheckTest < ActiveSupport::TestCase
  test "refreshes an expiring user token and updates discovered page tokens" do
    connection = SocialConnection.create!(
      provider: "meta",
      auth_mode: "facebook_login_for_business",
      connection_status: "connected",
      user_access_token: "old-user-token",
      user_token_expires_at: 2.days.from_now,
      granted_scopes: %w[pages_show_list pages_read_engagement pages_manage_posts instagram_basic instagram_content_publish]
    )
    page_target = connection.social_connection_targets.create!(
      target_type: "facebook_page",
      external_id: "page-123",
      name: "Test SL",
      access_token: "old-page-token",
      selected: true,
      status: "selected"
    )
    connection.social_connection_targets.create!(
      target_type: "instagram_account",
      external_id: "ig-123",
      username: "sl_test_26",
      parent_target: page_target,
      selected: true,
      status: "selected"
    )

    health_check = Meta::ConnectionHealthCheck.new(
      http_client: StubHttpClient.new(
        "https://graph.facebook.com/v25.0/debug_token" => {
          "data" => {
            "is_valid" => true,
            "expires_at" => 40.days.from_now.to_i,
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
      ),
      page_catalog_fetcher: StubPageCatalogFetcher.new(
        [
          Meta::PageCatalogFetcher::PageAccount.new(
            page_id: "page-123",
            page_name: "Test SL",
            page_access_token: "new-page-token",
            instagram_account_id: "ig-123",
            instagram_username: "sl_test_26"
          )
        ]
      ),
      token_refresher: StubTokenRefresher.new
    )

    status = health_check.call(connection:)

    connection.reload
    page_target.reload

    assert_predicate status, :ok?
    assert_equal "new-user-token", connection.user_access_token
    assert_equal "new-page-token", page_target.access_token
    assert connection.last_refresh_at.present?
  end

  private

  class StubTokenRefresher
    def call(token:)
      Struct.new(:access_token, :expires_at).new("new-user-token", 50.days.from_now)
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

  class StubHttpClient
    def initialize(responses)
      @responses = responses
    end

    def get_json!(url, params: {})
      @responses.fetch(url)
    end
  end
end
