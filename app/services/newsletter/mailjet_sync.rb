module Newsletter
  class MailjetSync
    PROVIDER = "mailjet"

    def self.configured?
      new.configured?
    end

    def self.call(subscriber, client: MailjetClient.new)
      new(client: client).call(subscriber)
    end

    def initialize(client: MailjetClient.new)
      @client = client
    end

    def configured?
      client.configured?
    end

    def call(subscriber)
      return false unless configured?
      return false unless subscriber.confirmed?

      response = client.subscribe(
        email: subscriber.email,
        properties: subscriber.interest_mailjet_properties
      )

      subscriber.update!(
        external_sync_status: NewsletterSubscriber::EXTERNAL_SYNC_STATUS_SYNCED,
        external_sync_provider: PROVIDER,
        external_contact_id: response["ContactID"],
        external_last_synced_at: Time.current,
        external_error_message: nil
      )

      true
    rescue StandardError => error
      subscriber.update_columns(
        external_sync_status: NewsletterSubscriber::EXTERNAL_SYNC_STATUS_FAILED,
        external_sync_provider: PROVIDER,
        external_error_message: error.message.to_s.truncate(500),
        updated_at: Time.current
      )
      raise
    end

    private

    attr_reader :client
  end
end
