require "test_helper"

class Newsletter::MailchimpSyncTest < ActiveSupport::TestCase
  test "marks subscriber as synced after successful mailchimp upsert" do
    subscriber = NewsletterSubscriber.create!(email: "sync@example.com", source: "homepage")
    client = SuccessfulMailchimpClient.new

    assert Newsletter::MailchimpSync.call(subscriber, client: client)

    subscriber.reload
    assert_equal NewsletterSubscriber::MAILCHIMP_STATUS_SYNCED, subscriber.mailchimp_status
    assert_equal "mailchimp-member-1", subscriber.mailchimp_member_id
    assert_not_nil subscriber.mailchimp_last_synced_at
    assert_nil subscriber.mailchimp_error_message
  end

  test "marks subscriber as failed when mailchimp sync raises" do
    subscriber = NewsletterSubscriber.create!(email: "failed@example.com", source: "homepage")
    client = FailingMailchimpClient.new

    assert_raises Newsletter::MailchimpClient::Error do
      Newsletter::MailchimpSync.call(subscriber, client: client)
    end

    subscriber.reload
    assert_equal NewsletterSubscriber::MAILCHIMP_STATUS_FAILED, subscriber.mailchimp_status
    assert_includes subscriber.mailchimp_error_message, "mailchimp unavailable"
  end

  test "returns false without changing subscriber when client is not configured" do
    subscriber = NewsletterSubscriber.create!(email: "pending@example.com", source: "homepage")
    client = UnconfiguredMailchimpClient.new

    assert_equal false, Newsletter::MailchimpSync.call(subscriber, client: client)

    subscriber.reload
    assert_equal NewsletterSubscriber::MAILCHIMP_STATUS_PENDING, subscriber.mailchimp_status
    assert_nil subscriber.mailchimp_member_id
  end

  SuccessfulMailchimpClient = Struct.new(:configured?) do
    def initialize
      super(true)
    end

    def upsert_member(email:, source:, subscribe_status:)
      {
        "id" => "mailchimp-member-1",
        "email_address" => email,
        "source" => source,
        "status" => subscribe_status
      }
    end
  end

  FailingMailchimpClient = Struct.new(:configured?) do
    def initialize
      super(true)
    end

    def upsert_member(**)
      raise Newsletter::MailchimpClient::Error, "mailchimp unavailable"
    end
  end

  UnconfiguredMailchimpClient = Struct.new(:configured?) do
    def initialize
      super(false)
    end
  end
end
