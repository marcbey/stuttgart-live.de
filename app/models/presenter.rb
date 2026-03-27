class Presenter < ApplicationRecord
  ProcessingError = Class.new(StandardError)

  has_one_attached :logo

  has_many :event_presenters, dependent: :restrict_with_error
  has_many :events, through: :event_presenters

  validates :name, presence: true
  validate :external_url_must_be_http_url
  validate :logo_must_be_attached
  validate :logo_must_be_image

  before_validation :normalize_attributes

  scope :ordered_by_name, -> { order(Arel.sql("LOWER(presenters.name) ASC"), :id) }

  def thumbnail_logo_variant
    processed_logo_representation(resize_to_limit: [ 160, 160 ])
  end

  def detail_logo_variant
    processed_logo_representation(resize_to_limit: [ 320, 320 ])
  end

  private

  def logo_representation(resize_to_limit:)
    return unless logo.attached?
    return logo unless logo.blob.variable?

    logo.variant(resize_to_limit:)
  end

  def processed_logo_representation(resize_to_limit:)
    representation = logo_representation(resize_to_limit:)
    return representation unless representation.respond_to?(:processed)

    representation.processed
  rescue LoadError, MiniMagick::Error => error
    Rails.logger.warn("Presenter logo optimization fallback for ##{id || 'new'}: #{error.class}: #{error.message}")
    logo
  rescue ActiveStorage::InvariableError, ImageProcessing::Error => error
    raise ProcessingError, processing_error_message(error)
  rescue StandardError => error
    raise unless vips_processing_error?(error)

    raise ProcessingError, processing_error_message(error)
  end

  def normalize_attributes
    self.name = name.to_s.strip
    self.description = description.to_s.strip.presence
    self.external_url = external_url.to_s.strip.presence
  end

  def external_url_must_be_http_url
    return if external_url.blank?

    uri = URI.parse(external_url)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:external_url, "muss mit http:// oder https:// beginnen")
  rescue URI::InvalidURIError
    errors.add(:external_url, "ist ungültig")
  end

  def logo_must_be_attached
    return if logo.attached?

    errors.add(:logo, "muss hochgeladen werden")
  end

  def logo_must_be_image
    return unless logo.attached?
    return if logo.content_type.to_s.start_with?("image/")

    errors.add(:logo, "muss ein Bild sein")
  end

  def processing_error_message(error)
    Rails.logger.warn("Presenter logo optimization failed for ##{id || 'new'}: #{error.class}: #{error.message}")
    "Logo konnte nicht für die Anzeige optimiert werden."
  end

  def vips_processing_error?(error)
    defined?(Vips::Error) && error.is_a?(Vips::Error)
  end
end
