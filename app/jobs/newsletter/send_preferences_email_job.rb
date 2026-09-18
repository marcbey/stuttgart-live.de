module Newsletter
  class SendPreferencesEmailJob < ApplicationJob
    queue_as :default
    discard_on ActiveJob::DeserializationError

    def perform(subscriber)
      return unless subscriber.confirmed?

      DeliverEmail.call(NewsletterMailer.preferences(subscriber))
    end
  end
end
