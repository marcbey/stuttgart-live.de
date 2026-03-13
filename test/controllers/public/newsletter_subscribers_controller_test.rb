require "test_helper"

class Public::NewsletterSubscribersControllerTest < ActionDispatch::IntegrationTest
  test "creates newsletter subscriber from homepage" do
    assert_difference("NewsletterSubscriber.count", 1) do
      post newsletter_subscribers_url, params: {
        newsletter_subscriber: { email: "new@example.com" }
      }
    end

    assert_redirected_to events_url
    assert_equal NewsletterSubscriber::MAILCHIMP_STATUS_PENDING, NewsletterSubscriber.order(:created_at).last.mailchimp_status
    follow_redirect!
    assert_includes response.body, "Danke. Du bist jetzt fuer den Newsletter eingetragen."
  end

  test "shows validation error for invalid email" do
    assert_no_difference("NewsletterSubscriber.count") do
      post newsletter_subscribers_url, params: {
        newsletter_subscriber: { email: "ungueltig" }
      }
    end

    assert_redirected_to events_url
    follow_redirect!
    assert_includes response.body, "Email is invalid"
  end
end
