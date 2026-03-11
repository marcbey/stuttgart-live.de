module Newsletter
  class MailchimpSync
    SUBSCRIBE_STATUSES = %w[pending subscribed].freeze

    def self.configured?
      new.configured?
    end

    def self.call(subscriber, client: MailchimpClient.new)
      new(client: client).call(subscriber)
    end

    def initialize(
      client: MailchimpClient.new,
      subscribe_status: ENV.fetch("MAILCHIMP_SUBSCRIBE_STATUS", "pending").to_s.strip
    )
      @client = client
      @subscribe_status = normalize_subscribe_status(subscribe_status)
    end

    def configured?
      client.configured?
    end

    def call(subscriber)
      return false unless configured?

      response = client.upsert_member(
        email: subscriber.email,
        source: subscriber.source,
        subscribe_status: subscribe_status
      )

      subscriber.update!(
        mailchimp_status: NewsletterSubscriber::MAILCHIMP_STATUS_SYNCED,
        mailchimp_member_id: response["id"],
        mailchimp_last_synced_at: Time.current,
        mailchimp_error_message: nil
      )

      true
    rescue StandardError => error
      subscriber.update_columns(
        mailchimp_status: NewsletterSubscriber::MAILCHIMP_STATUS_FAILED,
        mailchimp_error_message: error.message.to_s.truncate(500),
        updated_at: Time.current
      )
      raise
    end

    private

    attr_reader :client, :subscribe_status

    def normalize_subscribe_status(value)
      normalized = value.to_s.downcase
      return normalized if SUBSCRIBE_STATUSES.include?(normalized)

      "pending"
    end
  end
end
