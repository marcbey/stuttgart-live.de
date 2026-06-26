class NewsletterSubscriber < ApplicationRecord
  EXTERNAL_SYNC_STATUS_PENDING = "pending"
  EXTERNAL_SYNC_STATUS_SYNCED = "synced"
  EXTERNAL_SYNC_STATUS_FAILED = "failed"
  EXTERNAL_SYNC_STATUSES = [
    EXTERNAL_SYNC_STATUS_PENDING,
    EXTERNAL_SYNC_STATUS_SYNCED,
    EXTERNAL_SYNC_STATUS_FAILED
  ].freeze

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { case_sensitive: false }
  validates :source, presence: true
  validates :external_sync_status, inclusion: { in: EXTERNAL_SYNC_STATUSES }

  before_validation :normalize_email
  after_create_commit :enqueue_external_sync, if: :external_sync_configured?

  scope :external_sync_pending, -> { where(external_sync_status: EXTERNAL_SYNC_STATUS_PENDING) }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
    self.source = source.to_s.strip.presence || "homepage"
  end

  def enqueue_external_sync
    Newsletter::SyncSubscriberJob.perform_later(self)
  end

  def external_sync_configured?
    Newsletter::MailjetSync.configured?
  end
end
