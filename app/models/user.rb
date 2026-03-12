class User < ApplicationRecord
  ROLES = %w[admin editor blogger].freeze
  PASSWORD_MIN_LENGTH = 12
  PASSWORD_REQUIREMENTS_TEXT = "mindestens #{PASSWORD_MIN_LENGTH} Zeichen sowie Großbuchstaben, Kleinbuchstaben, Zahlen und Sonderzeichen".freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :published_events, class_name: "Event", foreign_key: :published_by_id, dependent: :nullify
  has_many :event_change_logs, dependent: :nullify
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
        value.match?(/\d/) &&
        value.match?(/[^A-Za-z0-9]/)
    end
end
