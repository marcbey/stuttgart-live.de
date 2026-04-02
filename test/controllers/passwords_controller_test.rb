require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  STRONG_PASSWORD = "Sicher123Pass".freeze

  setup { @user = users(:two) }

  test "new" do
    get new_password_path
    assert_response :success
    assert_select "body.page-auth-backoffice"
    assert_select ".app-nav-inner.app-nav-inner-backend.app-nav-inner-auth-backoffice", count: 1
    assert_select ".app-nav-links .app-nav-link-active", text: "Login"
    assert_select "section.backend-shell h1", text: "Passwort vergessen"
    assert_select "section.backend-section", minimum: 2
    assert_select "a[href='#{new_session_path}']", text: "Zurück zum Login"
  end

  test "create" do
    assert_emails 1 do
      post passwords_path, params: { email_address: @user.email_address }
    end
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "Magic-Link verschickt"
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "Magic-Link verschickt"
  end

  test "show signs the user in via magic link" do
    get password_path(@user.password_reset_token)

    assert_redirected_to edit_backend_account_password_path
    assert cookies[:session_id]

    follow_redirect!
    assert_notice "Magic-Link bestaetigt"
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "ungültig oder abgelaufen"
  end

  test "show with invalid magic link" do
    get password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "ungültig oder abgelaufen"
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: STRONG_PASSWORD, password_confirmation: STRONG_PASSWORD }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Passwort wurde aktualisiert"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no", password_confirmation: "match" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "stimmen nicht überein"
  end

  private
    def assert_notice(text)
      assert_select ".flash", /#{text}/
    end
end
