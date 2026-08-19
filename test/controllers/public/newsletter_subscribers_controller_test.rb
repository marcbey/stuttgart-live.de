require "test_helper"

class Public::NewsletterSubscribersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def expected_invalid_email_message(email)
    subscriber = NewsletterSubscriber.new(email: email, source: "homepage")
    subscriber.valid?
    subscriber.errors.full_messages.to_sentence
  end

  test "creates newsletter subscriber from homepage" do
    assert_enqueued_with(job: Newsletter::SendConfirmationEmailJob) do
      assert_difference("NewsletterSubscriber.count", 1) do
        post newsletter_subscribers_url, params: {
          newsletter_subscriber: { email: "new@example.com" }
        }
      end
    end

    subscriber = NewsletterSubscriber.order(:created_at).last
    assert_nil subscriber.confirmed_at
    assert_not_nil subscriber.confirmation_sent_at
    assert_equal NewsletterSubscriber::EXTERNAL_SYNC_STATUS_PENDING,
                 subscriber.external_sync_status
    assert_redirected_to events_url
    follow_redirect!
    assert_includes response.body, "Bitte bestätige jetzt deine E-Mail-Adresse."
  end

  test "creates newsletter subscriber with selected interests" do
    assert_difference("NewsletterSubscriber.count", 1) do
      post newsletter_subscribers_url, params: {
        newsletter_subscriber: {
          email: "interests@example.com",
          newsletter_interest_ids: [
            newsletter_interests(:pop).id,
            newsletter_interests(:rock).id
          ]
        }
      }
    end

    subscriber = NewsletterSubscriber.order(:created_at).last
    assert_equal(
      [ newsletter_interests(:pop).id, newsletter_interests(:rock).id ].sort,
      subscriber.newsletter_interest_ids.sort
    )
  end

  test "resends confirmation for existing unconfirmed email" do
    NewsletterSubscriber.create!(email: "pending@example.com", source: "homepage")
    clear_enqueued_jobs

    assert_enqueued_with(job: Newsletter::SendConfirmationEmailJob) do
      assert_no_difference("NewsletterSubscriber.count") do
        post newsletter_subscribers_url, params: {
          newsletter_subscriber: { email: "pending@example.com" }
        }
      end
    end

    assert_redirected_to events_url
  end

  test "confirms newsletter subscriber with valid token" do
    subscriber = NewsletterSubscriber.create!(email: "token@example.com", source: "homepage")
    clear_enqueued_jobs

    assert_enqueued_with(job: Newsletter::SyncSubscriberJob, args: [ subscriber ]) do
      get newsletter_confirmation_url(subscriber.confirmation_token)
    end

    assert_response :success
    assert_includes response.body, "Du bist jetzt eingetragen"
    assert_includes response.body, "Deine Newsletter-Anmeldung ist bestätigt"
    assert subscriber.reload.confirmed?
  end

  test "rejects invalid confirmation token" do
    get newsletter_confirmation_url("invalid-token")

    assert_response :unprocessable_entity
    assert_includes response.body, "Link ungültig oder abgelaufen"
  end

  test "confirmed duplicate email shows validation error" do
    existing = NewsletterSubscriber.create!(email: "new@example.com", source: "homepage", confirmed_at: Time.current)
    existing.newsletter_interests << newsletter_interests(:pop)
    clear_enqueued_jobs

    assert_no_enqueued_jobs only: Newsletter::SendConfirmationEmailJob do
      assert_no_difference("NewsletterSubscriber.count") do
        post newsletter_subscribers_url, params: {
          newsletter_subscriber: {
            email: "new@example.com",
            newsletter_interest_ids: [ newsletter_interests(:rock).id ]
          }
        }
      end
    end

    assert_equal [ newsletter_interests(:pop) ], existing.reload.newsletter_interests.to_a
    assert_redirected_to events_url
    follow_redirect!
    assert_includes response.body, "Email ist bereits vergeben"
  end

  test "legacy creates newsletter subscriber from homepage copy is now confirmation pending" do
    assert_difference("NewsletterSubscriber.count", 1) do
      post newsletter_subscribers_url, params: {
        newsletter_subscriber: { email: "legacy-new@example.com" }
      }
    end

    assert_redirected_to events_url
    follow_redirect!
    assert_includes response.body, "Bitte bestätige"
  end

  test "shows validation error for invalid email" do
    expected_message = expected_invalid_email_message("ungültig")

    assert_no_difference("NewsletterSubscriber.count") do
      post newsletter_subscribers_url, params: {
        newsletter_subscriber: { email: "ungültig" }
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
    assert_includes response.body, "Bitte bestätige deine E-Mail-Adresse."
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
    assert_includes response.body, "Bitte bestätige deine E-Mail-Adresse."
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
    assert_includes response.body, expected_invalid_email_message("ungültig")
    assert_includes response.body, "ungültig"
    assert_includes response.body, "<form"
    assert_includes response.body, "newsletter-signup-field"
  end

  test "shows duplicate email feedback inline while keeping the homepage field usable" do
    NewsletterSubscriber.create!(email: "existing@example.com", source: "homepage", confirmed_at: Time.current)

    assert_no_difference("NewsletterSubscriber.count") do
      post newsletter_subscribers_url,
           params: {
             context: "events_index",
             return_to: root_path,
             source: "homepage",
             newsletter_subscriber: { email: "existing@example.com" }
           },
           headers: { "Turbo-Frame" => "events-newsletter-signup" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, 'id="events-newsletter-signup"'
    assert_includes response.body, "Diese Mailadresse ist schon vorhanden."
    assert_includes response.body, 'class="newsletter-signup-feedback flash flash-alert"'
    assert_includes response.body, "newsletter-signup-field"
    assert_includes response.body, 'value="existing@example.com"'
    assert_equal 1, response.body.scan("newsletter-signup-field").length
    refute_includes response.body, "newsletter-signup-confirmation-error"
  end

  test "hides optional interest dropdown in newsletter form" do
    get root_url

    assert_response :success
    assert_includes response.body, "newsletter-signup-field"
    refute_includes response.body, "newsletter-signup-interests"
    refute_includes response.body, "Interessen auswählen"
  end
end
