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
      DeliverEmail.call(mail, client:)
    end

    private

    attr_reader :subscriber, :client
  end
end
