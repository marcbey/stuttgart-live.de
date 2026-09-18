require "test_helper"

class NewsletterSubscriberTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "normalizes email before validation" do
    subscriber = NewsletterSubscriber.create!(email: "  TEST@Example.com  ", source: "homepage")

    assert_equal "test@example.com", subscriber.email
  end

  test "rejects duplicate emails case-insensitively" do
    NewsletterSubscriber.create!(email: "hello@example.com", source: "homepage")
    duplicate = NewsletterSubscriber.new(email: "HELLO@example.com", source: "homepage")

    assert_not duplicate.valid?
    assert duplicate.errors.added?(:email, :taken, value: "hello@example.com")
  end

  test "enqueues confirmation email after explicit signup" do
    with_mailjet_config do
      assert_enqueued_with(job: Newsletter::SendConfirmationEmailJob) do
        signup_subscriber("queued@example.com")
      end
    end
  end

  test "does not enqueue mailjet sync before confirmation" do
    clear_enqueued_jobs
    with_mailjet_config do
      assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
        NewsletterSubscriber.create!(email: "local-only@example.com", source: "homepage")
      end
    end
  end

  test "confirm enqueues mailjet sync when mailjet is configured" do
    with_mailjet_config do
      subscriber = signup_subscriber("confirm@example.com")
      clear_enqueued_jobs

      assert_enqueued_with(job: Newsletter::SyncSubscriberJob, args: [ subscriber ]) do
        subscriber.confirm!
      end

      assert subscriber.confirmed?
    end
  end

  test "does not enqueue mailjet sync without a list id" do
    with_mailjet_config(list_id: nil) do
      assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
        signup_subscriber("missing-list@example.com").confirm!
      end
    end
  end

  test "does not enqueue mailjet sync for placeholder api key" do
    with_mailjet_config(api_key: "todo", secret_key: "secret-key", list_id: "123456") do
      assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
        signup_subscriber("placeholder@example.com").confirm!
      end
    end
  end

  test "plain record creation does not authorize sending or tracking" do
    assert_no_enqueued_jobs do
      subscriber = NewsletterSubscriber.create!(email: "ticket-buyer@example.com")
      assert_not subscriber.confirm!
      assert_not subscriber.open_tracking_consent?
      assert_empty subscriber.newsletter_consent_events
    end
  end

  test "legacy confirmed contacts do not acquire tracking consent" do
    subscriber = NewsletterSubscriber.create!(email: "legacy@example.com", confirmed_at: Time.current)
    assert subscriber.confirm!
    assert_not subscriber.open_tracking_consent?
    assert_not subscriber.click_tracking_consent?
    assert_empty subscriber.newsletter_consent_events
  end

  test "consent evidence cannot be overwritten" do
    subscriber = signup_subscriber("evidence@example.com")
    event = subscriber.newsletter_consent_events.first
    assert_raises ActiveRecord::ReadOnlyRecord do
      event.update!(open_tracking_consent: true)
    end
  end

  test "confirmed subscriber cannot be changed by another signup" do
    subscriber = signup_subscriber("confirmed@example.com")
    subscriber.confirm!
    assert_not subscriber.request_signup(newsletter_consent: "1", tracking_consent: "1")
    assert_not subscriber.reload.open_tracking_consent?
  end

  private

  def signup_subscriber(email)
    NewsletterSubscriber.new(email:, source: "homepage").tap do |subscriber|
      assert subscriber.request_signup(newsletter_consent: "1")
    end
  end

  def with_mailjet_config(api_key: "public-key", secret_key: "secret-key", list_id: "123456", api_endpoint: nil, &block)
    with_singleton_return_value(AppConfig, :mailjet_api_key, api_key) do
      with_singleton_return_value(AppConfig, :mailjet_secret_key, secret_key) do
        with_singleton_return_value(AppConfig, :mailjet_list_id, list_id) do
          with_singleton_return_value(AppConfig, :mailjet_api_endpoint, api_endpoint, &block)
        end
      end
    end
  ensure
    clear_enqueued_jobs
    clear_performed_jobs
  end

  def with_singleton_return_value(target, method_name, value)
    original_method = target.method(method_name)

    target.singleton_class.send(:define_method, method_name) { value }
    yield
  ensure
    target.singleton_class.send(:define_method, method_name, original_method)
  end
end
