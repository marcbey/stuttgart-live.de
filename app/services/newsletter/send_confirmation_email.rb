module Newsletter
  class SendConfirmationEmail
    def self.call(subscriber, client: MailjetClient.new)
      new(subscriber, client:).call
    end

    def initialize(subscriber, client:)
      @subscriber = subscriber
      @client = client
    end

    def call
      mail = NewsletterMailer.confirmation(subscriber)
      return mail.deliver_now unless client.api_configured?

      client.send_transactional_email(
        to: subscriber.email,
        subject: mail.subject,
        html: mail.html_part.body.decoded,
        text: mail.text_part.body.decoded
      )
    end

    private

    attr_reader :subscriber, :client
  end
end
