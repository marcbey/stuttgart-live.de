class SocialConnection < ApplicationRecord
  PROVIDERS = %w[meta].freeze
  AUTH_MODES = %w[facebook_login_for_business].freeze
  CONNECTION_STATUSES = %w[
    disconnected
    pending_selection
    connected
    expiring_soon
    refresh_failed
    reauth_required
    revoked
    error
  ].freeze

  encrypts :user_access_token

  has_many :social_connection_targets, dependent: :destroy
  has_many :publish_attempts, dependent: :nullify

  validates :provider, presence: true, inclusion: { in: PROVIDERS }, uniqueness: true
  validates :auth_mode, presence: true, inclusion: { in: AUTH_MODES }
  validates :connection_status, presence: true, inclusion: { in: CONNECTION_STATUSES }

  before_validation :normalize_attributes

  scope :meta_provider, -> { where(provider: "meta") }

  def self.meta
    find_or_initialize_by(provider: "meta") do |connection|
      connection.auth_mode = "facebook_login_for_business"
    end
  end

  def selected_facebook_page_target
    social_connection_targets.facebook_pages.selected.first
  end

  def selected_instagram_target
    social_connection_targets.instagram_accounts.selected.first
  end

  def connected?
    connection_status == "connected"
  end

  def pending_selection?
    connection_status == "pending_selection"
  end

  def reauth_required?
    connection_status == "reauth_required"
  end

  def expiring_soon?
    connection_status == "expiring_soon"
  end

  def refresh_failed?
    connection_status == "refresh_failed"
  end

  def revoked?
    connection_status == "revoked"
  end

  private

  def normalize_attributes
    self.provider = provider.to_s.strip.presence || "meta"
    self.auth_mode = auth_mode.to_s.strip.presence || "facebook_login_for_business"
    self.connection_status = connection_status.to_s.strip.presence || "disconnected"
    self.external_user_id = external_user_id.to_s.strip.presence
    self.user_access_token = user_access_token.to_s.strip.presence
    self.last_error = last_error.to_s.strip.presence
    self.granted_scopes = Array(granted_scopes).filter_map do |scope|
      scope.to_s.strip.presence
    end.uniq.sort
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
