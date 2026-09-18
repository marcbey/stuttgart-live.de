require "test_helper"

class NewsletterMailerTest < ActionMailer::TestCase
  test "preferences message is untracked and links to independent settings" do
    subscriber = NewsletterSubscriber.create!(email: "preferences-mail@example.com", confirmed_at: Time.current)
    mail = NewsletterMailer.preferences(subscriber)
    assert_equal [ subscriber.email ], mail.to
    assert_equal "0", mail["X-Mailjet-TrackOpen"].value
    assert_equal "0", mail["X-Mailjet-TrackClick"].value
    assert_includes mail.text_part.body.decoded, "/newsletter_preferences?token="
    assert_includes mail.html_part.body.decoded, "Tracking-Einstellungen verwalten"
  end

  test "confirmation contains confirmation link" do
    subscriber = NewsletterSubscriber.create!(email: "confirm-mail@example.com", source: "homepage")
    mail = NewsletterMailer.confirmation(subscriber)

    assert_equal [ "confirm-mail@example.com" ], mail.to
    assert_equal "Bitte bestätigen Sie Ihre Anmeldung zum StuttgartLIVE-Newsletter", mail.subject
    assert_equal "0", mail["X-Mailjet-TrackOpen"].value
    assert_equal "0", mail["X-Mailjet-TrackClick"].value
    assert_includes mail.text_part.body.decoded, Newsletter::ConsentText::CONFIRMATION_BODY
    assert_match %r{http://example\.com/newsletter/confirm/}, mail.text_part.body.to_s
    assert_match %r{http://example\.com/newsletter/confirm/}, mail.html_part.body.to_s
    assert_includes mail.text_part.body.to_s, "7 Tage gültig"
    assert_no_match(/Translation missing/, mail.text_part.body.to_s)
    assert_no_match(/Translation missing/, mail.html_part.body.to_s)
  end
end
