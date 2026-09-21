require "test_helper"

class Public::NewsletterFormSecurityTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @previous_protection = ApplicationController.allow_forgery_protection
    @previous_origin_check = ApplicationController.forgery_protection_origin_check
    ApplicationController.allow_forgery_protection = true
    ApplicationController.forgery_protection_origin_check = true
  end

  teardown do
    ApplicationController.allow_forgery_protection = @previous_protection
    ApplicationController.forgery_protection_origin_check = @previous_origin_check
  end

  test "signup permits a same origin browser submission with CSRF protection enabled" do
    get new_newsletter_subscriber_path
    assert_select "meta[name=referrer][content=same-origin]"
    token = css_select("input[name=authenticity_token]").first["value"]

    assert_enqueued_with(job: Newsletter::SendConfirmationEmailJob) do
      post newsletter_subscribers_path, params: {
        authenticity_token: token,
        newsletter_subscriber: { email: "browser-signup@example.com", newsletter_consent: "1" }
      }, headers: { "HTTP_ORIGIN" => request.base_url }
    end

    assert_response :redirect
    assert NewsletterSubscriber.find_by!(email: "browser-signup@example.com").pending_confirmation?
  end

  test "preference link request preserves the same origin policy" do
    get newsletter_preferences_path
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    assert_select "meta[name=referrer][content=same-origin]"
    token = css_select("input[name=authenticity_token]").first["value"]

    assert_no_enqueued_jobs do
      post newsletter_preferences_path, params: {
        authenticity_token: token, email: "unknown-browser@example.com"
      }, headers: { "HTTP_ORIGIN" => request.base_url }
    end

    assert_redirected_to newsletter_preferences_path
  end

  test "tracking preferences can be changed with CSRF protection enabled" do
    subscriber = NewsletterSubscriber.create!(email: "browser-preferences@example.com", confirmed_at: Time.current)
    path = newsletter_preferences_path(token: subscriber.preferences_token)
    get path
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    token = css_select("input[name=authenticity_token]").first["value"]

    patch path, params: { authenticity_token: token, tracking_consent: "1" },
                headers: { "HTTP_ORIGIN" => request.base_url }

    assert_response :redirect
    assert subscriber.reload.open_tracking_consent?
    assert subscriber.confirmed?
  end

  test "missing CSRF token is still rejected without creating a subscriber" do
    assert_no_enqueued_jobs do
      assert_no_difference("NewsletterSubscriber.count") do
        post newsletter_subscribers_path, params: {
          newsletter_subscriber: { email: "untrusted@example.com", newsletter_consent: "1" }
        }, headers: { "HTTP_ORIGIN" => "http://www.example.com" }
      end
    end

    assert_response :unprocessable_entity
  end

  test "cross origin submission is still rejected even with a valid token" do
    get new_newsletter_subscriber_path
    token = css_select("input[name=authenticity_token]").first["value"]

    assert_no_enqueued_jobs do
      assert_no_difference("NewsletterSubscriber.count") do
        post newsletter_subscribers_path, params: {
          authenticity_token: token,
          newsletter_subscriber: { email: "cross-origin@example.com", newsletter_consent: "1" }
        }, headers: { "HTTP_ORIGIN" => "https://another.example" }
      end
    end

    assert_response :unprocessable_entity
  end
end
