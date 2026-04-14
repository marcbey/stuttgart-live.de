class User < ApplicationRecord
  ROLES = %w[admin editor blogger].freeze
  PASSWORD_MIN_LENGTH = 8
  PASSWORD_REQUIREMENTS_TEXT = "mindestens #{PASSWORD_MIN_LENGTH} Zeichen sowie Großbuchstaben, Kleinbuchstaben und Zahlen".freeze
  MAX_FAILED_LOGIN_ATTEMPTS = 5
  LOGIN_LOCKOUT_PERIOD = 15.minutes

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :login_attempts, dependent: :nullify
  has_many :published_events, class_name: "Event", foreign_key: :published_by_id, dependent: :nullify
  has_many :event_change_logs, dependent: :nullify
  has_many :approved_event_social_posts, class_name: "EventSocialPost", foreign_key: :approved_by_id, dependent: :nullify
  has_many :published_event_social_posts, class_name: "EventSocialPost", foreign_key: :published_by_id, dependent: :nullify
  has_many :authored_blog_posts, class_name: "BlogPost", foreign_key: :author_id, dependent: :restrict_with_exception
  has_many :published_blog_posts, class_name: "BlogPost", foreign_key: :published_by_id, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :role, inclusion: { in: ROLES }
  validates :name, length: { maximum: 120 }, allow_blank: true
  validate :must_keep_an_admin_account, if: :admin_role_removed?
  validate :password_must_be_strong, if: :password_present?

  def admin?
    role == "admin"
  end

  def editor?
    role == "editor"
  end

  def blogger?
    role == "blogger"
  end

  def backend_access?
    admin? || editor?
  end

  def blog_access?
    admin? || editor? || blogger?
  end

  def login_locked?
    locked_until.present? && locked_until.future?
  end

  def register_failed_login!
    now = Time.current
    attempts = failed_login_attempts.to_i + 1
    updates = {
      failed_login_attempts: attempts,
      last_failed_login_at: now,
      updated_at: now
    }

    if attempts >= MAX_FAILED_LOGIN_ATTEMPTS
      updates[:locked_until] = now + LOGIN_LOCKOUT_PERIOD
    end

    update_columns(updates)
  end

  def clear_failed_login_attempts!
    update_columns(
      failed_login_attempts: 0,
      last_failed_login_at: nil,
      locked_until: nil,
      updated_at: Time.current
    )
  end

  private
    def password_present?
      password.present?
    end

    def admin_role_removed?
      persisted? && role_in_database == "admin" && role != "admin"
    end

    def must_keep_an_admin_account
      return if self.class.where(role: "admin").where.not(id: id).exists?

      errors.add(:role, "muss mindestens einen Admin behalten")
    end

    def password_must_be_strong
      return if strong_password?(password)

      errors.add(:password, "muss #{PASSWORD_REQUIREMENTS_TEXT} enthalten")
    end

    def strong_password?(value)
      value.length >= PASSWORD_MIN_LENGTH &&
        value.match?(/[[:lower:]]/) &&
        value.match?(/[[:upper:]]/) &&
        value.match?(/\d/)
    end
end
