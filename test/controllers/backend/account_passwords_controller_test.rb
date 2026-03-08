require "test_helper"

class Backend::AccountPasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "requires authentication" do
    get edit_backend_account_password_url

    assert_redirected_to new_session_url
  end

  test "updates the current users password and expires other sessions" do
    sign_in_as(@user)
    current_session_id = Current.session.id
    secondary_session = @user.sessions.create!

    patch backend_account_password_url, params: {
      user: {
        password: "new-password",
        password_confirmation: "new-password"
      }
    }

    assert_redirected_to edit_backend_account_password_url
    assert @user.reload.authenticate("new-password")
    assert Session.exists?(current_session_id)
    assert_not Session.exists?(secondary_session.id)
  end

  test "ignores role parameters on own password update" do
    sign_in_as(@user)

    patch backend_account_password_url, params: {
      user: {
        role: "admin",
        password: "new-password",
        password_confirmation: "new-password"
      }
    }

    assert_redirected_to edit_backend_account_password_url
    assert_equal "editor", @user.reload.role
  end
end
