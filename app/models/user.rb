class User < ApplicationRecord
  ROLES = %w[editor admin].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :published_events, class_name: "Event", foreign_key: :published_by_id, dependent: :nullify
  has_many :event_change_logs, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :role, inclusion: { in: ROLES }
  validates :name, length: { maximum: 120 }, allow_blank: true

  def admin?
    role == "admin"
  end

  def editor?
    role == "editor"
  end
end
