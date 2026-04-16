require "test_helper"

class SocialConnectionTest < ActiveSupport::TestCase
  test "meta defaults to instagram login for new connections" do
    connection = SocialConnection.meta

    assert_equal "meta", connection.provider
    assert_equal "instagram_login", connection.auth_mode
  end

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
    assert_predicate connection, :facebook_login_for_business?
  end

  test "recognizes instagram login connections" do
    connection = SocialConnection.create!(
      provider: "meta",
      auth_mode: "instagram_login",
      connection_status: "connected",
      user_access_token: "user-token"
    )

    assert_predicate connection, :instagram_login?
  end
end
