require "test_helper"

class SocialConnectionTest < ActiveSupport::TestCase
  test "resolves selected facebook and instagram targets" do
    connection = SocialConnection.create!(
      provider: "meta",
      auth_mode: "facebook_login_for_business",
      connection_status: "connected",
      user_access_token: "user-token"
    )
    page_target = connection.social_connection_targets.create!(
      target_type: "facebook_page",
      external_id: "page-1",
      selected: true,
      status: "selected"
    )
    instagram_target = connection.social_connection_targets.create!(
      target_type: "instagram_account",
      external_id: "ig-1",
      parent_target: page_target,
      selected: true,
      status: "selected"
    )

    assert_equal page_target, connection.selected_facebook_page_target
    assert_equal instagram_target, connection.selected_instagram_target
  end
end
