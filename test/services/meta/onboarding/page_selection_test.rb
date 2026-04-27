require "test_helper"

class Meta::Onboarding::PageSelectionTest < ActiveSupport::TestCase
  test "selects a facebook page without changing instagram targets" do
    connection = SocialConnection.create!(
      provider: "meta",
      auth_mode: "facebook_login_for_business",
      connection_status: "pending_selection",
      user_access_token: "user-token"
    )
    page_target = connection.social_connection_targets.create!(
      target_type: "facebook_page",
      external_id: "page-123",
      name: "Stuttgart Live",
      access_token: "page-token"
    )

    Meta::Onboarding::PageSelection.new(
      http_client: StubHttpClient.new
    ).call(connection:, facebook_target: page_target)

    connection.reload
    page_target.reload

    assert_equal "connected", connection.connection_status
    assert_predicate connection, :connected?
    assert page_target.selected?
    assert_equal "selected", page_target.status
    assert_nil connection.selected_instagram_target
  end

  private

  class StubHttpClient
    def get_json!(url, params: {})
      {
        "id" => "page-123",
        "name" => "Stuttgart Live",
        "instagram_business_account" => {
          "id" => "ig-123",
          "username" => "sl_test_26"
        }
      }
    end
  end
end
