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

  test "enqueues mailchimp sync when mailchimp is configured" do
    with_mailchimp_config do
      assert_enqueued_with(job: Newsletter::SyncSubscriberJob) do
        NewsletterSubscriber.create!(email: "queued@example.com", source: "homepage")
      end
    end
  end

  test "does not enqueue mailchimp sync when mailchimp is not configured" do
    clear_enqueued_jobs
    with_mailchimp_config(api_key: nil, list_id: nil, server_prefix: nil) do
      assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
        NewsletterSubscriber.create!(email: "local-only@example.com", source: "homepage")
      end
    end
  end

  test "does not enqueue mailchimp sync for placeholder api key" do
    with_mailchimp_config(api_key: "todo", list_id: "d55edf9631", server_prefix: "us3") do
      assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
        NewsletterSubscriber.create!(email: "placeholder@example.com", source: "homepage")
      end
    end
  end

  private

  def with_mailchimp_config(api_key: "test-us1", list_id: "audience123", server_prefix: "us1", &block)
    with_singleton_return_value(AppConfig, :mailchimp_api_key, api_key) do
      with_singleton_return_value(AppConfig, :mailchimp_list_id, list_id) do
        with_singleton_return_value(AppConfig, :mailchimp_server_prefix, server_prefix, &block)
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
