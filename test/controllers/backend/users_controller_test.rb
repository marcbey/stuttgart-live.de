require "test_helper"

class Backend::UsersControllerTest < ActionDispatch::IntegrationTest
  STRONG_PASSWORD = "Sicher123Pass".freeze

  setup do
    @admin = users(:two)
    @editor = users(:one)
    @blogger = users(:blogger)
  end

  test "admin can list users" do
    sign_in_as(@admin)

    get backend_users_url

    assert_response :success
    assert_includes response.body, "Benutzerverwaltung"
    assert_includes response.body, @editor.email_address
    assert_includes response.body, @blogger.email_address
  end

  test "editor cannot access user management" do
    sign_in_as(@editor)

    get backend_users_url

    assert_redirected_to backend_root_url
  end

  test "admin can create a user" do
    sign_in_as(@admin)

    assert_difference -> { User.count }, 1 do
      post backend_users_url, params: {
        user: {
          name: "Fresh User",
          email_address: "fresh@example.com",
          role: "blogger",
          password: STRONG_PASSWORD,
          password_confirmation: STRONG_PASSWORD
        }
      }
    end

    assert_redirected_to backend_users_url
    created_user = User.find_by!(email_address: "fresh@example.com")
    assert_equal "blogger", created_user.role
  end

  test "admin cannot create a user with a weak password" do
    sign_in_as(@admin)

    assert_no_difference -> { User.count } do
      post backend_users_url, params: {
        user: {
          name: "Weak User",
          email_address: "weak@example.com",
          role: "blogger",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, User::PASSWORD_REQUIREMENTS_TEXT
  end

  test "admin can change another users role and password" do
    sign_in_as(@admin)
    existing_session = @editor.sessions.create!

    patch backend_user_url(@editor), params: {
      user: {
        role: "blogger",
        password: STRONG_PASSWORD,
        password_confirmation: STRONG_PASSWORD
      }
    }

    assert_redirected_to backend_users_url
    assert_equal "blogger", @editor.reload.role
    assert @editor.authenticate(STRONG_PASSWORD)
    assert_not Session.exists?(existing_session.id)
  end

  test "admin cannot change own role" do
    sign_in_as(@admin)

    patch backend_user_url(@admin), params: {
      user: {
        role: "editor"
      }
    }

    assert_redirected_to backend_users_url
    assert_equal "admin", @admin.reload.role
  end
end
