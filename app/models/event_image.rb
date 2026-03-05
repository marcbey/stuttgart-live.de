class EventImage < ApplicationRecord
  PURPOSE_SLIDER = "slider".freeze
  PURPOSE_DETAIL_HERO = "detail_hero".freeze
  PURPOSE_GRID_TILE = "grid_tile".freeze
  PURPOSES = [
    PURPOSE_SLIDER,
    PURPOSE_DETAIL_HERO,
    PURPOSE_GRID_TILE
  ].freeze

  GRID_VARIANT_1X1 = "1x1".freeze
  GRID_VARIANT_2X1 = "2x1".freeze
  GRID_VARIANT_1X2 = "1x2".freeze
  GRID_VARIANT_2X2 = "2x2".freeze
  GRID_VARIANTS = [
    GRID_VARIANT_1X1,
    GRID_VARIANT_2X1,
    GRID_VARIANT_1X2,
    GRID_VARIANT_2X2
  ].freeze

  belongs_to :event
  has_one_attached :file

  scope :ordered, -> { order(created_at: :asc, id: :asc) }
  scope :slider, -> { where(purpose: PURPOSE_SLIDER) }
  scope :detail_hero, -> { where(purpose: PURPOSE_DETAIL_HERO) }
  scope :grid_tile, -> { where(purpose: PURPOSE_GRID_TILE) }

  validates :purpose, presence: true, inclusion: { in: PURPOSES }
  validates :grid_variant, inclusion: { in: GRID_VARIANTS }, allow_nil: true
  validates :alt_text, length: { maximum: 240 }, allow_blank: true
  validates :sub_text, length: { maximum: 500 }, allow_blank: true
  validate :grid_variant_presence_for_grid_tile
  validate :grid_variant_absence_for_non_grid_tile
  validate :single_detail_hero_per_event, if: :detail_hero?
  validate :single_grid_variant_per_event, if: :grid_tile?
  validate :file_attached
  validate :file_is_image

  before_validation :normalize_text_fields

  def slider?
    purpose == PURPOSE_SLIDER
  end

  def detail_hero?
    purpose == PURPOSE_DETAIL_HERO
  end

  def grid_tile?
    purpose == PURPOSE_GRID_TILE
  end

  def label
    return "slider" if slider?
    return "detail hero" if detail_hero?
    return "grid #{grid_variant}" if grid_tile?

    purpose.to_s
  end

  private

  def normalize_text_fields
    self.purpose = purpose.to_s.strip
    self.grid_variant = grid_variant.to_s.strip.presence
    self.alt_text = alt_text.to_s.strip.presence
    self.sub_text = sub_text.to_s.strip.presence
  end

  def grid_variant_presence_for_grid_tile
    return unless grid_tile?
    return if grid_variant.present?

    errors.add(:grid_variant, "muss für Grid-Bilder gesetzt sein")
  end

  def grid_variant_absence_for_non_grid_tile
    return if grid_tile?
    return if grid_variant.blank?

    errors.add(:grid_variant, "ist nur für Grid-Bilder erlaubt")
  end

  def single_detail_hero_per_event
    return if event_id.blank?

    relation = self.class.where(event_id: event_id, purpose: PURPOSE_DETAIL_HERO)
    relation = relation.where.not(id: id) if persisted?
    return unless relation.exists?

    errors.add(:purpose, "darf nur einmal pro Event als Detail-Hero vorkommen")
  end

  def single_grid_variant_per_event
    return if event_id.blank? || grid_variant.blank?

    relation = self.class.where(
      event_id: event_id,
      purpose: PURPOSE_GRID_TILE,
      grid_variant: grid_variant
    )
    relation = relation.where.not(id: id) if persisted?
    return unless relation.exists?

    errors.add(:grid_variant, "ist für dieses Event bereits belegt")
  end

  def file_attached
    return if file.attached?

    errors.add(:file, "muss hochgeladen werden")
  end

  def file_is_image
    return unless file.attached?

    content_type = file.content_type.to_s
    return if content_type.start_with?("image/")

    errors.add(:file, "muss ein Bild sein")
  end
end
