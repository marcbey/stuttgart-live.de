class NewsletterSubscriber < ApplicationRecord
  CONFIRMATION_TOKEN_PURPOSE = :newsletter_confirmation
  CONFIRMATION_TOKEN_EXPIRY = 7.days
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
  after_create_commit :send_confirmation_email, unless: :confirmed?

  scope :external_sync_pending, -> { where(external_sync_status: EXTERNAL_SYNC_STATUS_PENDING) }
  scope :confirmed, -> { where.not(confirmed_at: nil) }

  has_many :newsletter_subscriber_interests, dependent: :destroy
  has_many :newsletter_interests, through: :newsletter_subscriber_interests

  def self.find_by_normalized_email(email)
    normalized_email = email.to_s.strip.downcase
    return if normalized_email.blank?

    where("lower(email) = ?", normalized_email).first
  end

  def confirmation_token
    signed_id(purpose: CONFIRMATION_TOKEN_PURPOSE, expires_in: CONFIRMATION_TOKEN_EXPIRY)
  end

  def confirmed?
    confirmed_at.present?
  end

  def pending_confirmation?
    !confirmed?
  end

  def newsletter_interest_ids=(ids)
    @newsletter_interest_ids = NewsletterInterest.find_public_ids(ids).pluck(:id)
    super(@newsletter_interest_ids)
  end

  def newsletter_interest_ids
    @newsletter_interest_ids || super
  end

  def interest_mailjet_properties
    newsletter_interests.each_with_object({}) do |interest, properties|
      properties[interest.mailjet_property_name] = true
    end
  end

  def confirm!
    return true if confirmed?

    update!(confirmed_at: Time.current)
    enqueue_external_sync! if external_sync_configured?
    true
  end

  def send_confirmation_email
    update_column(:confirmation_sent_at, Time.current) if persisted?
    Newsletter::SendConfirmationEmailJob.perform_later(self)
  end

  def enqueue_external_sync!
    Newsletter::SyncSubscriberJob.perform_later(self)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
    self.source = source.to_s.strip.presence || "homepage"
  end

  def external_sync_configured?
    Newsletter::MailjetSync.configured?
  end
end
