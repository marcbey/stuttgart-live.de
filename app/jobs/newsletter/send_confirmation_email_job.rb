module Newsletter
  class SendConfirmationEmailJob < ApplicationJob
    queue_as :default

    def perform(subscriber)
      return if subscriber.confirmed? || subscriber.newsletter_consent_at.nil?

      Newsletter::SendConfirmationEmail.call(subscriber)
    end
  end
end
