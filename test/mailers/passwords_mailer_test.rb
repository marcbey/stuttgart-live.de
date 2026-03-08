require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "magic_link contains a sign-in link" do
    user = users(:two)
    mail = PasswordsMailer.magic_link(user)

    assert_equal [ user.email_address ], mail.to
    assert_equal "Dein Magic-Link fuer Stuttgart Live", mail.subject
    assert_match %r{http://example\.com/passwords/}, mail.text_part.body.to_s
    assert_match %r{http://example\.com/passwords/}, mail.html_part.body.to_s
    assert_includes mail.text_part.body.to_s, "15 Minuten"
  end
end
