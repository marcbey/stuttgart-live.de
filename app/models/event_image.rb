class EventImage < ApplicationRecord
  DEFAULT_CARD_FOCUS_X = 50.0
  DEFAULT_CARD_FOCUS_Y = 50.0
  DEFAULT_CARD_ZOOM = 100.0
  HERO_FOCUS_TOP = "top".freeze
  HERO_FOCUS_CENTER = "center".freeze
  HERO_FOCUS_BOTTOM = "bottom".freeze
  PURPOSE_SLIDER = "slider".freeze
  PURPOSE_DETAIL_HERO = "detail_hero".freeze
  PURPOSES = [
    PURPOSE_SLIDER,
    PURPOSE_DETAIL_HERO
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
  HERO_FOCUS_POSITIONS = [
    HERO_FOCUS_TOP,
    HERO_FOCUS_CENTER,
    HERO_FOCUS_BOTTOM
  ].freeze

  belongs_to :event
  has_one_attached :file

  scope :ordered, -> { order(created_at: :asc, id: :asc) }
  scope :slider, -> { where(purpose: PURPOSE_SLIDER) }
  scope :detail_hero, -> { where(purpose: PURPOSE_DETAIL_HERO) }

  validates :purpose, presence: true, inclusion: { in: PURPOSES }
  validates :grid_variant, inclusion: { in: GRID_VARIANTS }, allow_nil: true
  validates :hero_focus_position, inclusion: { in: HERO_FOCUS_POSITIONS }, allow_blank: true
  validates :alt_text, length: { maximum: 240 }, allow_blank: true
  validates :sub_text, length: { maximum: 500 }, allow_blank: true
  validates :card_focus_x, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :card_focus_y, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :card_zoom, numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 300 }
  validate :grid_variant_absence_for_slider
  validate :single_detail_hero_per_event, if: :detail_hero?
  validate :file_attached
  validate :file_is_image

  before_validation :normalize_text_fields

  def slider?
    purpose == PURPOSE_SLIDER
  end

  def detail_hero?
    purpose == PURPOSE_DETAIL_HERO
  end

  def label
    return "slider" if slider?
    return "event image" if detail_hero?

    purpose.to_s
  end

  def card_focus_x_value
    card_focus_x.nil? ? DEFAULT_CARD_FOCUS_X : card_focus_x.to_f
  end

  def card_focus_y_value
    card_focus_y.nil? ? DEFAULT_CARD_FOCUS_Y : card_focus_y.to_f
  end

  def card_zoom_value
    zoom = card_zoom.to_f
    zoom.positive? ? zoom : DEFAULT_CARD_ZOOM
  end

  def hero_focus_position_value
    value = hero_focus_position.to_s
    HERO_FOCUS_POSITIONS.include?(value) ? value : HERO_FOCUS_CENTER
  end

  private

  def normalize_text_fields
    self.purpose = purpose.to_s.strip
    self.grid_variant = grid_variant.to_s.strip.presence
    self.hero_focus_position = hero_focus_position.to_s.strip.presence
    self.alt_text = alt_text.to_s.strip.presence
    self.sub_text = sub_text.to_s.strip.presence
    self.card_focus_x = normalize_percentage(card_focus_x, fallback: DEFAULT_CARD_FOCUS_X)
    self.card_focus_y = normalize_percentage(card_focus_y, fallback: DEFAULT_CARD_FOCUS_Y)
    self.card_zoom = normalize_percentage(card_zoom, fallback: DEFAULT_CARD_ZOOM)
  end

  def normalize_percentage(value, fallback:)
    return fallback if value.blank?

    value.to_f.round(2)
  end

  def grid_variant_absence_for_slider
    return unless slider?
    return if grid_variant.blank?

    errors.add(:grid_variant, "ist nur für das Eventbild erlaubt")
  end

  def single_detail_hero_per_event
    return if event_id.blank?

    relation = self.class.where(event_id: event_id, purpose: PURPOSE_DETAIL_HERO)
    relation = relation.where.not(id: id) if persisted?
    return unless relation.exists?

    errors.add(:purpose, "darf nur einmal pro Event als Detail-Hero vorkommen")
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
