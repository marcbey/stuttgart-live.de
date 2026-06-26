require "test_helper"

class Newsletter::MailjetSyncTest < ActiveSupport::TestCase
  test "marks subscriber as synced after successful mailjet subscription" do
    subscriber = NewsletterSubscriber.create!(email: "sync@example.com", source: "homepage")
    client = SuccessfulMailjetClient.new

    assert Newsletter::MailjetSync.call(subscriber, client: client)

    subscriber.reload
    assert_equal NewsletterSubscriber::EXTERNAL_SYNC_STATUS_SYNCED, subscriber.external_sync_status
    assert_equal "mailjet", subscriber.external_sync_provider
    assert_equal "mailjet-contact-1", subscriber.external_contact_id
    assert_not_nil subscriber.external_last_synced_at
    assert_nil subscriber.external_error_message
    assert_equal [ { email: "sync@example.com" } ], client.requests
  end

  test "marks subscriber as failed when mailjet sync raises" do
    subscriber = NewsletterSubscriber.create!(email: "failed@example.com", source: "homepage")
    client = FailingMailjetClient.new

    assert_raises Newsletter::MailjetClient::Error do
      Newsletter::MailjetSync.call(subscriber, client: client)
    end

    subscriber.reload
    assert_equal NewsletterSubscriber::EXTERNAL_SYNC_STATUS_FAILED, subscriber.external_sync_status
    assert_equal "mailjet", subscriber.external_sync_provider
    assert_includes subscriber.external_error_message, "mailjet unavailable"
  end

  test "returns false without changing subscriber when client is not configured" do
    subscriber = NewsletterSubscriber.create!(email: "pending@example.com", source: "homepage")
    client = UnconfiguredMailjetClient.new

    assert_equal false, Newsletter::MailjetSync.call(subscriber, client: client)

    subscriber.reload
    assert_equal NewsletterSubscriber::EXTERNAL_SYNC_STATUS_PENDING, subscriber.external_sync_status
    assert_nil subscriber.external_contact_id
    assert_nil subscriber.external_sync_provider
  end

  SuccessfulMailjetClient = Struct.new(:configured?, :requests) do
    def initialize
      super(true, [])
    end

    def subscribe(email:)
      requests << { email: email }

      {
        "ContactID" => "mailjet-contact-1",
        "Email" => email
      }
    end
  end

  FailingMailjetClient = Struct.new(:configured?) do
    def initialize
      super(true)
    end

    def subscribe(**)
      raise Newsletter::MailjetClient::Error, "mailjet unavailable"
    end
  end

  UnconfiguredMailjetClient = Struct.new(:configured?) do
    def initialize
      super(false)
    end
  end
end
