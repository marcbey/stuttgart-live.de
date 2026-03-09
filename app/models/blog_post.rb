class BlogPost < ApplicationRecord
  STATUSES = %w[draft published].freeze

  belongs_to :author, class_name: "User"
  belongs_to :published_by, class_name: "User", optional: true

  has_one_attached :cover_image
  has_rich_text :body

  validates :title, presence: true, length: { maximum: 180 }
  validates :teaser, presence: true, length: { maximum: 320 }
  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :published_at, presence: true, if: :published?
  validate :body_must_be_present
  validate :cover_image_must_be_image

  before_validation :normalize_attributes
  before_validation :assign_slug, if: :slug_needed?

  scope :ordered_for_backend, -> { includes(:author, :published_by).with_attached_cover_image.order(updated_at: :desc, id: :desc) }
  scope :published_live, -> { where(status: "published").where("published_at <= ?", Time.current).order(published_at: :desc, id: :desc) }

  def published?
    status == "published"
  end

  def scheduled?
    published? && published_at.present? && published_at.future?
  end

  def live?
    published? && published_at.present? && published_at <= Time.current
  end

  def display_status
    return "Entwurf" unless published?
    return "Geplant" if scheduled?

    "Veröffentlicht"
  end

  private
    def normalize_attributes
      self.title = title.to_s.strip
      self.teaser = teaser.to_s.strip
      self.slug = slug.to_s.strip.parameterize.presence || slug
    end

    def slug_needed?
      slug.blank?
    end

    def assign_slug
      base = title.to_s.parameterize
      base = "news" if base.blank?

      candidate = base
      suffix = 2

      while self.class.where.not(id: id).exists?(slug: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end

      self.slug = candidate
    end

    def body_must_be_present
      return if body.to_plain_text.strip.present?

      errors.add(:body, "muss ausgefüllt werden")
    end

    def cover_image_must_be_image
      return unless cover_image.attached?
      return if cover_image.content_type.to_s.start_with?("image/")

      errors.add(:cover_image, "muss ein Bild sein")
    end
end
