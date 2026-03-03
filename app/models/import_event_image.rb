require "uri"

class ImportEventImage < ApplicationRecord
  PLACEHOLDER_PATTERNS = [
    /blank\.gif(?:\?|$)/i,
    /placeholder/i,
    /no[-_]?image/i,
    /default[-_]?image/i,
    /dummy/i
  ].freeze

  ASPECT_HINTS = %w[portrait square landscape unknown].freeze
  ROLES = %w[cover gallery thumb].freeze

  belongs_to :import_event,
    polymorphic: true,
    foreign_key: :import_event_id,
    foreign_type: :import_class,
    inverse_of: :import_event_images

  validates :import_class, :source, :image_type, :image_url, :role, :aspect_hint, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :aspect_hint, inclusion: { in: ASPECT_HINTS }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :image_url, uniqueness: {
    scope: [ :import_class, :import_event_id, :source, :image_type ],
    case_sensitive: false
  }

  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_fields

  def self.normalize_image_url(raw_value)
    value = raw_value.to_s.strip
    return nil if value.blank?
    return nil unless value.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
    return nil if placeholder_url?(value)

    value
  end

  def self.placeholder_url?(url)
    value = url.to_s
    PLACEHOLDER_PATTERNS.any? { |pattern| value.match?(pattern) }
  end

  def self.derive_aspect_hint(url:, image_type:)
    value = url.to_s
    if (match = value.match(/(\d{2,5})x(\d{2,5})/i))
      width = match[1].to_i
      height = match[2].to_i
      return "square" if width == height
      return "landscape" if width > height
      return "portrait"
    end

    normalized_type = image_type.to_s.downcase
    return "square" if normalized_type.include?("small") || normalized_type.include?("thumb")
    return "square" if normalized_type.include?("big")

    "unknown"
  end

  def self.derive_role(source:, image_type:)
    normalized_type = image_type.to_s.downcase

    return "cover" if normalized_type.include?("big") || normalized_type == "large"
    return "thumb" if normalized_type.include?("small") || normalized_type.include?("thumb")

    if source.to_s == "easyticket"
      return "cover" if normalized_type == "image_url"
    end

    "gallery"
  end

  private

  def normalize_fields
    self.import_class = import_class.to_s.strip
    self.source = source.to_s.strip.downcase
    self.image_type = image_type.to_s.strip
    self.role = role.to_s.strip.presence || "gallery"
    self.aspect_hint = aspect_hint.to_s.strip.presence || "unknown"
    self.image_url = image_url.to_s.strip
  end
end
