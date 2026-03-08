require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @blogger = users(:blogger)
  end

  test "new" do
    get new_session_path
    assert_response :success
    assert_select "a[href='#{new_password_path}']", text: "Passwort vergessen"
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @editor.email_address, password: "password" }

    assert_redirected_to backend_root_path
    assert cookies[:session_id]
  end

  test "create with blogger credentials redirects to the public root" do
    post session_path, params: { email_address: @blogger.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @editor.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(@editor)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
