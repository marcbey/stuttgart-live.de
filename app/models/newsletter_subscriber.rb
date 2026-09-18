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
  attribute :newsletter_consent, :boolean
  attribute :tracking_consent, :boolean
  validate :require_newsletter_consent, on: :signup

  generates_token_for :newsletter_confirmation, expires_in: CONFIRMATION_TOKEN_EXPIRY do
    confirmation_nonce
  end
  generates_token_for :newsletter_preferences, expires_in: 2.days

  scope :external_sync_pending, -> { where(external_sync_status: EXTERNAL_SYNC_STATUS_PENDING) }
  scope :confirmed, -> { where.not(confirmed_at: nil) }

  has_many :newsletter_subscriber_interests, dependent: :destroy
  has_many :newsletter_interests, through: :newsletter_subscriber_interests
  has_many :newsletter_consent_events, dependent: :delete_all

  def self.find_by_normalized_email(email)
    normalized_email = email.to_s.strip.downcase
    return if normalized_email.blank?

    where("lower(email) = ?", normalized_email).first
  end

  def confirmation_token
    generate_token_for(:newsletter_confirmation)
  end

  def preferences_token
    generate_token_for(:newsletter_preferences)
  end

  def request_signup(attributes)
    with_lock do
      if confirmed?
        errors.add(:email, :taken)
        raise ActiveRecord::RecordInvalid, self
      end
      assign_attributes(attributes)
      self.newsletter_consent_at = Time.current
      self.consent_version = Newsletter::ConsentText::VERSION
      self.confirmation_nonce = SecureRandom.hex(16)
      self.requested_tracking_consent = tracking_consent == true
      save!(context: :signup)
      record_consent!("signup_requested", open_tracking: requested_tracking_consent, click_tracking: requested_tracking_consent)
    end
    send_confirmation_email
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def update_tracking_consent!(consent)
    with_lock do
      granted = consent == true || consent == "1"
      update!(open_tracking_consent: granted, click_tracking_consent: granted)
      record_consent!(granted ? "tracking_granted" : "tracking_withdrawn")
    end
    Newsletter::SyncTrackingPreferencesJob.perform_later(self) if external_sync_configured?
  end

  def tracking_mailjet_properties
    { "stuttgartlive_open_tracking_consent" => open_tracking_consent?,
      "stuttgartlive_click_tracking_consent" => click_tracking_consent? }
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

  def confirm!(token: nil)
    with_lock do
      self.class.find_by_token_for!(:newsletter_confirmation, token) if token
      return true if confirmed?
      return false if newsletter_consent_at.nil? || confirmation_nonce.blank?

      update!(confirmed_at: Time.current, open_tracking_consent: requested_tracking_consent, click_tracking_consent: requested_tracking_consent)
      record_consent!("signup_confirmed")
    end
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

  def require_newsletter_consent
    errors.add(:base, "Bitte stimmen Sie dem Newsletter-Empfang zu.") unless newsletter_consent == true
  end

  def record_consent!(action, open_tracking: open_tracking_consent?, click_tracking: click_tracking_consent?)
    signup = newsletter_consent_events.where(action: "signup_requested").order(:id).last if action == "signup_confirmed"
    newsletter_consent_events.create!(
      email:, action:, source:, consent_version: signup&.consent_version || Newsletter::ConsentText::VERSION,
      consent_text: signup&.consent_text || Newsletter::ConsentText.snapshot, occurred_at: Time.current,
      open_tracking_consent: open_tracking, click_tracking_consent: click_tracking
    )
  end

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
    self.source = source.to_s.strip.presence || "homepage"
  end

  def external_sync_configured?
    Newsletter::MailjetSync.configured?
  end
end
