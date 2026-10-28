require "test_helper"

class UserTest < ActiveSupport::TestCase
  STRONG_PASSWORD = "Sicher123Pass".freeze

  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "supports blogger as a valid role" do
    user = User.new(
      email_address: "blogger-role@example.com",
      password: STRONG_PASSWORD,
      password_confirmation: STRONG_PASSWORD,
      role: "blogger"
    )

    assert user.valid?
  end

  test "requires strong passwords when setting a password" do
    user = User.new(
      email_address: "weak-password@example.com",
      password: "password",
      password_confirmation: "password",
      role: "editor"
    )

    assert_not user.valid?
    assert_includes user.errors[:password], "muss #{User::PASSWORD_REQUIREMENTS_TEXT} enthalten"
  end

  test "accepts strong passwords without special characters" do
    user = User.new(
      email_address: "no-special-char@example.com",
      password: STRONG_PASSWORD,
      password_confirmation: STRONG_PASSWORD,
      role: "editor"
    )

    assert user.valid?
  end

  test "blogger has blog access but no event backend access" do
    blogger = users(:blogger)

    assert blogger.blog_access?
    assert_not blogger.backend_access?
  end

  test "locks the account after too many failed logins" do
    user = users(:one)

    User::MAX_FAILED_LOGIN_ATTEMPTS.times { user.register_failed_login! }

    user.reload

    assert user.login_locked?
    assert_equal User::MAX_FAILED_LOGIN_ATTEMPTS, user.failed_login_attempts
    assert_in_delta User::LOGIN_LOCKOUT_PERIOD.from_now.to_i, user.locked_until.to_i, 5
  end

  test "clears failed login tracking" do
    user = users(:one)
    user.update_columns(
      failed_login_attempts: 3,
      last_failed_login_at: Time.current,
      locked_until: 5.minutes.from_now
    )

    user.clear_failed_login_attempts!
    user.reload

    assert_equal 0, user.failed_login_attempts
    assert_nil user.last_failed_login_at
    assert_nil user.locked_until
  end

  test "does not allow removing the last admin role" do
    admin = users(:two)

    assert_not admin.update(role: "editor")
    assert_includes admin.errors[:role], "muss mindestens einen Admin behalten"
  end

  test "does not allow destroying the last admin or their sessions" do
    admin = users(:two)
    session = admin.sessions.create!

    assert_no_difference [ -> { User.count }, -> { Session.count } ] do
      assert_not admin.destroy
    end

    assert_includes admin.errors[:base], "Der letzte Admin kann nicht gelöscht werden."
    assert User.exists?(admin.id)
    assert Session.exists?(session.id)
  end

  test "protects the last admin even with an unsaved role change" do
    admin = users(:two)
    admin.role = "editor"

    assert_no_difference -> { User.count } do
      assert_not admin.destroy
    end
  end

  test "can destroy an admin when another admin remains" do
    users(:one).update!(role: "admin")

    assert_difference -> { User.count }, -1 do
      assert users(:two).destroy
    end

    assert_equal 1, User.where(role: "admin").count
  end

  test "can destroy a non admin and their sessions" do
    editor = users(:one)
    session = editor.sessions.create!

    assert_difference -> { User.count }, -1 do
      assert editor.destroy
    end

    assert_not Session.exists?(session.id)
    assert User.exists?(users(:two).id)
  end

  test "deleting a user preserves newsletters they created" do
    issue = NewsletterIssue.create!(title: "Kulturwoche", subject: "Deine Events", created_by: users(:one))

    assert_difference -> { User.count }, -1 do
      assert users(:one).destroy
    end

    assert_nil issue.reload.created_by_id
  end

  test "deleting a user preserves newsletters they sent" do
    issue = NewsletterIssue.create!(title: "Kulturwoche", subject: "Deine Events", sent_by: users(:one))

    assert_difference -> { User.count }, -1 do
      assert users(:one).destroy
    end

    assert_nil issue.reload.sent_by_id
  end

  test "deleting a user preserves their social publishing history" do
    post = EventSocialPost.create!(event: events(:published_one), platform: "instagram", caption: "Unser Tipp")
    attempt = post.publish_attempts.create!(platform: "instagram", initiated_by: users(:one))

    assert_difference -> { User.count }, -1 do
      assert users(:one).destroy
    end

    assert_nil attempt.reload.initiated_by_id
    assert EventSocialPost.exists?(post.id)
  end
end
