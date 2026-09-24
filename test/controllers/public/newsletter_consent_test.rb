require "test_helper"

class Public::NewsletterConsentTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "email alone cannot subscribe or send a confirmation" do
    assert_no_enqueued_jobs do
      assert_no_difference("NewsletterSubscriber.count") do
        post newsletter_subscribers_path, params: { newsletter_subscriber: { email: "no-consent@example.com" } }
      end
    end
  end

  test "compact signup opens consent form without saving or sending" do
    assert_no_enqueued_jobs do
      assert_no_difference("NewsletterSubscriber.count") do
        post newsletter_subscribers_path, params: {
          signup_step: "details", source: "footer",
          newsletter_subscriber: { email: "details@example.com" }
        }
      end
    end

    assert_response :success
    assert_select "a.newsletter-consent-brand[aria-label='Stuttgart Live Startseite']" do
      assert_select ".newsletter-consent-brand-city", text: "STUTTGART"
      assert_select ".newsletter-consent-brand-live", text: "LIVE"
      assert_select "img", count: 0
    end
    assert_select "input[type=email][value='details@example.com']"
    assert_select "input[type=checkbox][name='newsletter_subscriber[newsletter_consent]'][required]"
    assert_select "input[type=checkbox][name='newsletter_subscriber[tracking_consent]']:not([required]):not([checked])"
    assert_select "label", text: /Südwestdeutsche Konzertdirektion Erwin Russ GmbH.*Mailjet.*personenbezogen auswertet/
    assert_select "p", text: /Tracking-Einstellungen.*ohne den Newsletter abbestellen zu müssen/
    assert_select "a[href=?]", datenschutz_path
  end

  test "compact forms use a full page transition for the consent step" do
    get root_path
    assert_select "form.design-preview-footer-newsletter-form[data-turbo='false'] input[name=signup_step][value=details]"
    assert_select "form.design-preview-menu-newsletter-form[data-turbo='false'] input[name=signup_step][value=details]"
  end

  test "signup and confirmation record separate evidence and tracking is optional" do
    subscribe(tracking: "0")
    subscriber = NewsletterSubscriber.find_by!(email: "consent@example.com")
    assert_not subscriber.confirmed?
    assert_not subscriber.open_tracking_consent?
    assert_equal "signup_requested", subscriber.newsletter_consent_events.last.action

    get newsletter_confirmation_path(subscriber.confirmation_token)
    assert_response :success
    assert subscriber.reload.confirmed?
    assert_not subscriber.open_tracking_consent?
    assert_not subscriber.click_tracking_consent?
    evidence = subscriber.newsletter_consent_events.order(:id).last
    assert_equal "signup_confirmed", evidence.action
    assert_equal subscriber.email, evidence.email
    assert_equal "2026-09-23", evidence.consent_version
    assert_includes evidence.consent_text.fetch("newsletter"), "Südwestdeutschen Konzertdirektion Erwin Russ GmbH"
    assert_includes evidence.consent_text.fetch("tracking"), "mithilfe des Newsletter-Dienstes Mailjet"
    assert_includes evidence.consent_text.fetch("tracking"), "ohne den Newsletter abbestellen zu müssen"
    assert evidence.occurred_at
  end

  test "tracking starts only after confirmation and old tokens cannot confirm changed choices" do
    subscribe(tracking: "0")
    subscriber = NewsletterSubscriber.find_by!(email: "consent@example.com")
    previous_token = subscriber.confirmation_token
    subscribe(tracking: "1")
    assert_not subscriber.reload.open_tracking_consent?

    get newsletter_confirmation_path(previous_token)
    assert_response :unprocessable_entity
    assert_not subscriber.reload.confirmed?

    get newsletter_confirmation_path(subscriber.confirmation_token)
    assert_response :success
    assert subscriber.reload.open_tracking_consent?
    assert subscriber.click_tracking_consent?
    assert_no_difference("NewsletterConsentEvent.count") do
      get newsletter_confirmation_path(subscriber.confirmation_token)
    end
  end

  test "tracking withdrawal preserves newsletter and is not performed by opening a link" do
    subscribe(tracking: "1")
    subscriber = NewsletterSubscriber.find_by!(email: "consent@example.com")
    subscriber.confirm!
    confirmed_at = subscriber.confirmed_at
    token = subscriber.preferences_token
    clear_enqueued_jobs

    get newsletter_preferences_path(token:)
    assert_response :success
    assert subscriber.reload.open_tracking_consent?

    assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
      patch newsletter_preferences_path(token:), params: { tracking_consent: "0" }
    end
    assert_redirected_to newsletter_preferences_path(token:)
    assert_equal confirmed_at, subscriber.reload.confirmed_at
    assert_not subscriber.open_tracking_consent?
    assert_not subscriber.click_tracking_consent?
    assert_equal "tracking_withdrawn", subscriber.newsletter_consent_events.order(:id).last.action
  end

  test "invalid preferences token cannot update a contact" do
    patch newsletter_preferences_path(token: "invalid"), params: { tracking_consent: "1" }
    assert_response :unprocessable_entity
  end

  test "tracking preference emails do not disclose whether a contact exists" do
    subscriber = NewsletterSubscriber.create!(email: "existing-preferences@example.com", confirmed_at: Time.current)
    assert_enqueued_with(job: Newsletter::SendPreferencesEmailJob, args: [ subscriber ]) do
      post newsletter_preferences_path, params: { email: "EXISTING-PREFERENCES@example.com" }
    end
    known_notice = flash[:notice]
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      post newsletter_preferences_path, params: { email: "unknown-preferences@example.com" }
    end
    assert_equal known_notice, flash[:notice]
  end

  test "expired and unconfirmed preferences tokens cannot change consent" do
    subscribe(tracking: "0")
    subscriber = NewsletterSubscriber.find_by!(email: "consent@example.com")
    patch newsletter_preferences_path(token: subscriber.preferences_token), params: { tracking_consent: "1" }
    assert_response :unprocessable_entity
    assert_not subscriber.reload.open_tracking_consent?

    subscriber.confirm!
    token = subscriber.preferences_token
    travel 3.days do
      patch newsletter_preferences_path(token:), params: { tracking_consent: "1" }
      assert_response :unprocessable_entity
    end
    assert_not subscriber.reload.open_tracking_consent?
  end

  test "expired confirmation cannot activate newsletter or tracking" do
    subscribe(tracking: "1")
    subscriber = NewsletterSubscriber.find_by!(email: "consent@example.com")
    token = subscriber.confirmation_token
    travel 8.days do
      get newsletter_confirmation_path(token)
      assert_response :unprocessable_entity
    end
    assert_not subscriber.reload.confirmed?
    assert_not subscriber.open_tracking_consent?
  end

  private

  def subscribe(tracking:)
    post newsletter_subscribers_path, params: {
      newsletter_subscriber: { email: "consent@example.com", newsletter_consent: "1", tracking_consent: tracking }
    }
  end
end
