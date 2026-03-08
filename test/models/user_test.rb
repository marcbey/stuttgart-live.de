require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "supports blogger as a valid role" do
    user = User.new(
      email_address: "blogger-role@example.com",
      password: "password",
      password_confirmation: "password",
      role: "blogger"
    )

    assert user.valid?
  end

  test "does not allow removing the last admin role" do
    admin = users(:two)

    assert_not admin.update(role: "editor")
    assert_includes admin.errors[:role], "muss mindestens einen Admin behalten"
  end
end
