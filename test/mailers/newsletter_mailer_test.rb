require "test_helper"

class NewsletterMailerTest < ActionMailer::TestCase
  test "confirmation contains confirmation link" do
    subscriber = NewsletterSubscriber.create!(email: "confirm-mail@example.com", source: "homepage")
    mail = NewsletterMailer.confirmation(subscriber)

    assert_equal [ "confirm-mail@example.com" ], mail.to
    assert_equal "Bitte bestätige deine Newsletter-Anmeldung", mail.subject
    assert_match %r{http://example\.com/newsletter/confirm/}, mail.text_part.body.to_s
    assert_match %r{http://example\.com/newsletter/confirm/}, mail.html_part.body.to_s
    assert_includes mail.text_part.body.to_s, "7 Tage gültig"
    assert_no_match(/Translation missing/, mail.text_part.body.to_s)
    assert_no_match(/Translation missing/, mail.html_part.body.to_s)
  end
end
