require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @blogger = users(:blogger)
  end

  test "new" do
    get new_session_path
    assert_response :success
    assert_select "body.page-auth-backoffice"
    assert_select ".app-nav-inner.app-nav-inner-backend.app-nav-inner-auth-backoffice", count: 1
    assert_select ".app-nav-links .app-nav-link-active", text: "Login"
    assert_select "section.backend-shell h1", text: "Login"
    assert_select "section.backend-section", minimum: 2
    assert_select "a[href='#{new_password_path}']", text: "Passwort vergessen"
  end

  test "login route redirects to new session" do
    get login_path

    assert_redirected_to new_session_path
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @editor.email_address, password: "password" }

    assert_redirected_to backend_root_path
    assert cookies[:session_id]
    assert_equal "successful", LoginAttempt.recent_first.first.outcome
  end

  test "create with blogger credentials redirects to the blog backend" do
    post session_path, params: { email_address: @blogger.email_address, password: "password" }

    assert_redirected_to backend_blog_posts_path
    assert cookies[:session_id]
    assert_equal "successful", LoginAttempt.recent_first.first.outcome
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @editor.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    assert_equal 1, @editor.reload.failed_login_attempts
    attempt = LoginAttempt.recent_first.first
    assert_equal "failed", attempt.outcome
    assert_equal @editor.email_address, attempt.email_address
  end

  test "create locks the account after too many failed credentials" do
    User::MAX_FAILED_LOGIN_ATTEMPTS.times do
      post session_path, params: { email_address: @editor.email_address, password: "wrong" }
      assert_redirected_to new_session_path
    end

    @editor.reload

    assert @editor.login_locked?
    assert_equal "failed", LoginAttempt.recent_first.first.outcome
  end

  test "create rejects locked users even with a correct password" do
    @editor.update_columns(
      failed_login_attempts: User::MAX_FAILED_LOGIN_ATTEMPTS,
      last_failed_login_at: Time.current,
      locked_until: 10.minutes.from_now
    )

    post session_path, params: { email_address: @editor.email_address, password: "password" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    assert_equal "Zu viele Fehlversuche. Bitte später erneut versuchen.", flash[:alert]
    assert_equal "locked", LoginAttempt.recent_first.first.outcome
  end

  test "create resets failed login tracking after a successful login" do
    @editor.update_columns(
      failed_login_attempts: 2,
      last_failed_login_at: 2.minutes.ago,
      locked_until: nil
    )

    post session_path, params: { email_address: @editor.email_address, password: "password" }

    assert_redirected_to backend_root_path
    @editor.reload
    assert_equal 0, @editor.failed_login_attempts
    assert_nil @editor.last_failed_login_at
    assert_nil @editor.locked_until
  end

  test "destroy" do
    sign_in_as(@editor)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
