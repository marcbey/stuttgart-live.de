class StaticPage < ApplicationRecord
  SYSTEM_SLUGS = {
    "privacy" => "datenschutz",
    "imprint" => "impressum",
    "terms" => "agb",
    "accessibility" => "barrierefreiheit",
    "contact" => "kontakt"
  }.freeze

  RESERVED_SLUGS = %w[
    400
    404
    422
    500
    backend
    begleitformular
    blog
    datenschutz
    errors
    events
    impressum
    kontakt
    login
    news
    passwords
    rails
    search
    session
    up
    agb
    barrierefreiheit
  ].freeze
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/.freeze

  has_rich_text :body

  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT }
  validates :title, presence: true, length: { maximum: 180 }
  validates :kicker, length: { maximum: 80 }, allow_blank: true
  validates :intro, length: { maximum: 500 }, allow_blank: true
  validates :system_key, uniqueness: true, allow_nil: true
  validate :body_must_be_present
  validate :slug_must_not_be_reserved
  validate :system_page_slug_must_match
  validate :system_page_slug_cannot_change, on: :update

  before_validation :normalize_slug
  before_validation :assign_slug, if: :slug_needed?
  before_destroy :ensure_destroyable

  scope :with_page_content, -> { with_rich_text_body_and_embeds }
  scope :system_pages, -> { where.not(system_key: nil).order(:system_key) }
  scope :custom_pages, -> { where(system_key: nil).order(:title, :id) }

  def system_page?
    system_key.present?
  end

  def destroyable?
    !system_page?
  end

  def card_layout?
    body&.body&.to_html.to_s.include?("info-page-card")
  end

  private
    def slug_needed?
      slug.blank? && title.present?
    end

    def assign_slug
      self.slug = title.to_s.parameterize
    end

    def normalize_slug
      value = slug.to_s.strip
      return self.slug = nil if value.blank?

      self.slug =
        if value.include?("/")
          value.downcase
        else
          value.parameterize.presence
        end
    end

    def body_must_be_present
      return if body&.to_plain_text.to_s.strip.present?

      errors.add(:body, "muss ausgefüllt werden")
    end

    def slug_must_not_be_reserved
      return if slug.blank?
      return if system_slug_allowed?
      return unless RESERVED_SLUGS.include?(slug)

      errors.add(:slug, "ist reserviert")
    end

    def system_page_slug_must_match
      return if system_key.blank?

      expected_slug = SYSTEM_SLUGS[system_key]
      return if expected_slug.present? && slug == expected_slug

      errors.add(:slug, "muss für diese Systemseite #{expected_slug} sein")
    end

    def system_page_slug_cannot_change
      return unless system_page?
      return unless will_save_change_to_slug?

      errors.add(:slug, "kann für Systemseiten nicht geändert werden")
    end

    def system_slug_allowed?
      return false if system_key.blank?

      slug == SYSTEM_SLUGS[system_key]
    end

    def ensure_destroyable
      return if destroyable?

      errors.add(:base, "Systemseiten können nicht gelöscht werden")
      throw :abort
    end
end
