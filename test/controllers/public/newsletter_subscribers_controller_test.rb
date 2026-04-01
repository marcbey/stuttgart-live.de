require "test_helper"

class Public::NewsletterSubscribersControllerTest < ActionDispatch::IntegrationTest
  def expected_invalid_email_message(email)
    subscriber = NewsletterSubscriber.new(email: email, source: "homepage")
    subscriber.valid?
    subscriber.errors.full_messages.to_sentence
  end

  test "creates newsletter subscriber from homepage" do
    assert_difference("NewsletterSubscriber.count", 1) do
      post newsletter_subscribers_url, params: {
        newsletter_subscriber: { email: "new@example.com" }
      }
    end

    assert_redirected_to events_url
    assert_equal NewsletterSubscriber::MAILCHIMP_STATUS_PENDING, NewsletterSubscriber.order(:created_at).last.mailchimp_status
    follow_redirect!
    assert_includes response.body, "Danke! Du bist jetzt für den Newsletter eingetragen."
  end

  test "shows validation error for invalid email" do
    expected_message = expected_invalid_email_message("ungueltig")

    assert_no_difference("NewsletterSubscriber.count") do
      post newsletter_subscribers_url, params: {
        newsletter_subscriber: { email: "ungueltig" }
      }
    end

    assert_redirected_to events_url
    follow_redirect!
    assert_includes response.body, expected_message
  end

  test "replaces the events newsletter form with a confirmation after turbo signup" do
    assert_difference("NewsletterSubscriber.count", 1) do
      post newsletter_subscribers_url,
           params: {
             context: "events_index",
             return_to: root_path,
             source: "homepage",
             newsletter_subscriber: { email: "frame@example.com" }
           },
           headers: { "Turbo-Frame" => "events-newsletter-signup" }
    end

    assert_response :success
    assert_includes response.body, 'id="events-newsletter-signup"'
    assert_includes response.body, "Danke!"
    assert_includes response.body, "Du bist jetzt eingetragen!"
    refute_includes response.body, "<form"
  end

  test "replaces the news newsletter form with a confirmation after turbo signup" do
    assert_difference("NewsletterSubscriber.count", 1) do
      post newsletter_subscribers_url,
           params: {
             context: "news_index",
             return_to: news_index_path,
             source: "news_index",
             newsletter_subscriber: { email: "news@example.com" }
           },
           headers: { "Turbo-Frame" => "news-index-newsletter-signup" }
    end

    assert_response :success
    assert_includes response.body, 'id="news-index-newsletter-signup"'
    assert_includes response.body, "Danke!"
    assert_includes response.body, "Du bist jetzt für den Newsletter eingetragen."
    refute_includes response.body, "<form"
  end

  test "shows inline validation errors in the turbo frame" do
    assert_no_difference("NewsletterSubscriber.count") do
      post newsletter_subscribers_url,
           params: {
             context: "events_index",
             return_to: root_path,
             source: "homepage",
             newsletter_subscriber: { email: "ungültig" }
           },
           headers: { "Turbo-Frame" => "events-newsletter-signup" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, 'id="events-newsletter-signup"'
    assert_includes response.body, "Diese Mailadresse ist schon vorhanden."
    assert_includes response.body, "ungültig"
    assert_includes response.body, "<form"
  end
end
