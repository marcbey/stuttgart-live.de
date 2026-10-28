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
    assert_includes response.body, "Passwörter"
    assert_select "section.backend-section.backend-table-section", count: 1
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

  test "user list offers confirmed deletion and explains the last admin protection" do
    sign_in_as(@admin)

    get backend_users_url

    assert_select "form[action=?][data-turbo-confirm]", backend_user_path(@editor) do
      assert_select "input[name='_method'][value='delete']"
      assert_select "button", text: "Löschen"
    end
    assert_select "form[action=?]", backend_user_path(@admin), count: 0
    assert_includes response.body, "Der letzte Admin kann nicht gelöscht werden."
  end

  test "admin can delete a user and their sessions" do
    sign_in_as(@admin)
    existing_session = @editor.sessions.create!

    assert_difference -> { User.count }, -1 do
      delete backend_user_url(@editor)
    end

    assert_redirected_to backend_users_url
    assert_equal "Benutzer wurde gelöscht.", flash[:notice]
    assert_not Session.exists?(existing_session.id)
  end

  test "admin can delete another admin when an admin remains" do
    @editor.update!(role: "admin")
    sign_in_as(@admin)

    assert_difference -> { User.count }, -1 do
      delete backend_user_url(@editor)
    end

    assert_redirected_to backend_users_url
    assert User.exists?(@admin.id)
  end

  test "admin cannot delete the last admin" do
    sign_in_as(@admin)
    session_id = Current.session.id

    assert_no_difference [ -> { User.count }, -> { Session.count } ] do
      delete backend_user_url(@admin)
    end

    assert_redirected_to backend_users_url
    assert_equal "Der letzte Admin kann nicht gelöscht werden.", flash[:alert]
    assert Session.exists?(session_id)
  end

  test "admin can delete their own account when another admin remains" do
    @editor.update!(role: "admin")
    sign_in_as(@admin)
    session_id = Current.session.id

    assert_difference -> { User.count }, -1 do
      delete backend_user_url(@admin)
    end

    assert_redirected_to new_session_url
    assert_not Session.exists?(session_id)
    assert_empty cookies[:session_id]

    get backend_users_url

    assert_redirected_to new_session_url
  end

  test "editor cannot delete users" do
    sign_in_as(@editor)

    assert_no_difference -> { User.count } do
      delete backend_user_url(@blogger)
    end

    assert_redirected_to backend_root_url
  end

  test "blogger cannot delete users" do
    sign_in_as(@blogger)

    assert_no_difference -> { User.count } do
      delete backend_user_url(@editor)
    end

    assert_redirected_to root_url
  end

  test "unauthenticated visitors cannot delete users" do
    assert_no_difference -> { User.count } do
      delete backend_user_url(@editor)
    end

    assert_redirected_to new_session_url
  end

  test "deleting an author keeps the account and blog posts with an explanation" do
    post = BlogPost.create!(title: "Beitrag", teaser: "Ein Teaser.", body: "<div>Inhalt</div>", author: @editor)
    existing_session = @editor.sessions.create!
    sign_in_as(@admin)

    assert_no_difference [ -> { User.count }, -> { BlogPost.count }, -> { Session.count } ] do
      delete backend_user_url(@editor)
    end

    assert_redirected_to backend_users_url
    assert_equal "Benutzer mit eigenen Blogbeiträgen können nicht gelöscht werden.", flash[:alert]
    assert_equal @editor, post.reload.author
    assert Session.exists?(existing_session.id)
  end
end
