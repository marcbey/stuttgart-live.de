module Newsletter
  class SyncSubscriberJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: 30.seconds, attempts: 3
    discard_on ActiveJob::DeserializationError

    def perform(subscriber)
      return unless subscriber.confirmed?

      Newsletter::MailjetSync.call(subscriber)
    end
  end
end
