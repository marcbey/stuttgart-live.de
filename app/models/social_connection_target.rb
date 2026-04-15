class SocialConnectionTarget < ApplicationRecord
  TARGET_TYPES = %w[facebook_page instagram_account].freeze
  STATUSES = %w[available selected missing error revoked].freeze

  encrypts :access_token

  belongs_to :social_connection
  belongs_to :parent_target, class_name: "SocialConnectionTarget", optional: true
  has_many :child_targets,
    class_name: "SocialConnectionTarget",
    foreign_key: :parent_target_id,
    dependent: :nullify,
    inverse_of: :parent_target
  has_many :publish_attempts, dependent: :nullify

  validates :target_type, presence: true, inclusion: { in: TARGET_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :external_id, presence: true, uniqueness: { scope: [ :social_connection_id, :target_type ] }

  before_validation :normalize_attributes

  scope :facebook_pages, -> { where(target_type: "facebook_page") }
  scope :instagram_accounts, -> { where(target_type: "instagram_account") }
  scope :selected, -> { where(selected: true) }

  def facebook_page?
    target_type == "facebook_page"
  end

  def instagram_account?
    target_type == "instagram_account"
  end

  def display_name
    name.presence || username.presence || external_id
  end

  private

  def normalize_attributes
    self.target_type = target_type.to_s.strip
    self.status = status.to_s.strip.presence || "available"
    self.external_id = external_id.to_s.strip
    self.name = name.to_s.strip.presence
    self.username = username.to_s.strip.presence
    self.access_token = access_token.to_s.strip.presence
    self.last_error = last_error.to_s.strip.presence
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
