module Newsletter
  class SyncTrackingPreferencesJob < ApplicationJob
    queue_as :default
    retry_on Newsletter::MailjetClient::Error, wait: 30.seconds, attempts: 3
    discard_on ActiveJob::DeserializationError

    def perform(subscriber)
      return unless subscriber.confirmed?

      client = MailjetClient.new
      return unless client.configured?

      subscriber.with_lock do
        client.sync_tracking_preferences(email: subscriber.email, properties: subscriber.tracking_mailjet_properties)
      end
    end
  end
end
