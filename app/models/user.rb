class User < ApplicationRecord
  ROLES = %w[admin editor blogger].freeze

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
    def admin_role_removed?
      persisted? && role_in_database == "admin" && role != "admin"
    end

    def must_keep_an_admin_account
      return if self.class.where(role: "admin").where.not(id: id).exists?

      errors.add(:role, "muss mindestens einen Admin behalten")
    end
end
