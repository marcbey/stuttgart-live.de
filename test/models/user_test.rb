require "test_helper"

class UserTest < ActiveSupport::TestCase
  STRONG_PASSWORD = "Sicher123!Pass".freeze

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

  test "blogger has blog access but no event backend access" do
    blogger = users(:blogger)

    assert blogger.blog_access?
    assert_not blogger.backend_access?
  end

  test "does not allow removing the last admin role" do
    admin = users(:two)

    assert_not admin.update(role: "editor")
    assert_includes admin.errors[:role], "muss mindestens einen Admin behalten"
  end
end
