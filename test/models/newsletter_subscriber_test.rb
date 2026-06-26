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

  test "enqueues mailjet sync when mailjet is configured" do
    with_mailjet_config do
      assert_enqueued_with(job: Newsletter::SyncSubscriberJob) do
        NewsletterSubscriber.create!(email: "queued@example.com", source: "homepage")
      end
    end
  end

  test "does not enqueue mailjet sync when mailjet is not configured" do
    clear_enqueued_jobs
    with_mailjet_config(api_key: nil, secret_key: nil, list_id: nil) do
      assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
        NewsletterSubscriber.create!(email: "local-only@example.com", source: "homepage")
      end
    end
  end

  test "does not enqueue mailjet sync without a list id" do
    with_mailjet_config(list_id: nil) do
      assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
        NewsletterSubscriber.create!(email: "missing-list@example.com", source: "homepage")
      end
    end
  end

  test "does not enqueue mailjet sync for placeholder api key" do
    with_mailjet_config(api_key: "todo", secret_key: "secret-key", list_id: "123456") do
      assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
        NewsletterSubscriber.create!(email: "placeholder@example.com", source: "homepage")
      end
    end
  end

  private

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
