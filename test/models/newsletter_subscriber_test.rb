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
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "enqueues mailchimp sync when mailchimp is configured" do
    with_mailchimp_env do
      assert_enqueued_with(job: Newsletter::SyncSubscriberJob) do
        NewsletterSubscriber.create!(email: "queued@example.com", source: "homepage")
      end
    end
  end

  test "does not enqueue mailchimp sync when mailchimp is not configured" do
    clear_enqueued_jobs
    previous_api_key = ENV["MAILCHIMP_API_KEY"]
    previous_list_id = ENV["MAILCHIMP_LIST_ID"]
    previous_server_prefix = ENV["MAILCHIMP_SERVER_PREFIX"]
    ENV["MAILCHIMP_API_KEY"] = nil
    ENV["MAILCHIMP_LIST_ID"] = nil
    ENV["MAILCHIMP_SERVER_PREFIX"] = nil

    assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
      NewsletterSubscriber.create!(email: "local-only@example.com", source: "homepage")
    end
  ensure
    ENV["MAILCHIMP_API_KEY"] = previous_api_key
    ENV["MAILCHIMP_LIST_ID"] = previous_list_id
    ENV["MAILCHIMP_SERVER_PREFIX"] = previous_server_prefix
  end

  test "does not enqueue mailchimp sync for placeholder api key" do
    previous_api_key = ENV["MAILCHIMP_API_KEY"]
    previous_list_id = ENV["MAILCHIMP_LIST_ID"]
    previous_server_prefix = ENV["MAILCHIMP_SERVER_PREFIX"]
    ENV["MAILCHIMP_API_KEY"] = "todo"
    ENV["MAILCHIMP_LIST_ID"] = "d55edf9631"
    ENV["MAILCHIMP_SERVER_PREFIX"] = "us3"

    assert_no_enqueued_jobs only: Newsletter::SyncSubscriberJob do
      NewsletterSubscriber.create!(email: "placeholder@example.com", source: "homepage")
    end
  ensure
    ENV["MAILCHIMP_API_KEY"] = previous_api_key
    ENV["MAILCHIMP_LIST_ID"] = previous_list_id
    ENV["MAILCHIMP_SERVER_PREFIX"] = previous_server_prefix
  end

  private

  def with_mailchimp_env
    previous_api_key = ENV["MAILCHIMP_API_KEY"]
    previous_list_id = ENV["MAILCHIMP_LIST_ID"]
    previous_server_prefix = ENV["MAILCHIMP_SERVER_PREFIX"]
    ENV["MAILCHIMP_API_KEY"] = "test-us1"
    ENV["MAILCHIMP_LIST_ID"] = "audience123"
    ENV["MAILCHIMP_SERVER_PREFIX"] = "us1"
    yield
  ensure
    ENV["MAILCHIMP_API_KEY"] = previous_api_key
    ENV["MAILCHIMP_LIST_ID"] = previous_list_id
    ENV["MAILCHIMP_SERVER_PREFIX"] = previous_server_prefix
    clear_enqueued_jobs
    clear_performed_jobs
  end
end
