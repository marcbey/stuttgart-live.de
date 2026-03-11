require "test_helper"

class Newsletter::SyncSubscriberJobTest < ActiveJob::TestCase
  test "delegates to mailchimp sync service" do
    subscriber = NewsletterSubscriber.create!(email: "job@example.com", source: "homepage")
    captured_subscriber = nil

    sync_class = Newsletter::MailchimpSync.singleton_class
    sync_class.alias_method :__original_call_for_test, :call
    sync_class.define_method(:call) do |record, **|
      captured_subscriber = record
      true
    end

    Newsletter::SyncSubscriberJob.perform_now(subscriber)

    assert_equal subscriber, captured_subscriber
  ensure
    sync_class.alias_method :call, :__original_call_for_test
    sync_class.remove_method :__original_call_for_test
  end
end
