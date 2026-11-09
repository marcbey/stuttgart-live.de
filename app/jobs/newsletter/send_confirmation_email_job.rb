require "digest"

module Newsletter
  class SendConfirmationEmailJob < ApplicationJob
    queue_as :default

    retry_on MailjetClient::DailySendingLimitExceeded, wait: 1.day, attempts: 3, jitter: 0.1
    discard_on ActiveJob::DeserializationError

    before_enqueue { @signup_digest ||= signup_digest_for(arguments.first) }

    def serialize
      # Keep the original perform signature compatible with workers from a prior release.
      super.merge("signup_digest" => @signup_digest)
    end

    def deserialize(job_data)
      super
      @signup_digest = job_data["signup_digest"]
    end

    def perform(subscriber)
      return if subscriber.confirmed? || subscriber.newsletter_consent_at.nil? || subscriber.confirmation_nonce.blank?

      signup_digest = signup_digest_for(subscriber)
      if @signup_digest.nil?
        return if enqueued_at && enqueued_at < subscriber.newsletter_consent_at

        # Bind retries of legacy jobs to the signup they attempted.
        @signup_digest = signup_digest
      end
      return if @signup_digest != signup_digest

      Newsletter::SendConfirmationEmail.call(subscriber)
    end

    private

    def signup_digest_for(subscriber)
      Digest::SHA256.hexdigest(subscriber.confirmation_nonce.to_s)
    end
  end
end
