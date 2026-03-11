class NewsletterSubscriber < ApplicationRecord
  MAILCHIMP_STATUS_PENDING = "pending"
  MAILCHIMP_STATUS_SYNCED = "synced"
  MAILCHIMP_STATUS_FAILED = "failed"
  MAILCHIMP_STATUSES = [
    MAILCHIMP_STATUS_PENDING,
    MAILCHIMP_STATUS_SYNCED,
    MAILCHIMP_STATUS_FAILED
  ].freeze

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { case_sensitive: false }
  validates :source, presence: true
  validates :mailchimp_status, inclusion: { in: MAILCHIMP_STATUSES }

  before_validation :normalize_email
  after_create_commit :enqueue_mailchimp_sync, if: :mailchimp_sync_configured?

  scope :mailchimp_pending, -> { where(mailchimp_status: MAILCHIMP_STATUS_PENDING) }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
    self.source = source.to_s.strip.presence || "homepage"
  end

  def enqueue_mailchimp_sync
    Newsletter::SyncSubscriberJob.perform_later(self)
  end

  def mailchimp_sync_configured?
    Newsletter::MailchimpSync.configured?
  end
end
