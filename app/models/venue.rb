class Venue < ApplicationRecord
  ProcessingError = Class.new(StandardError)

  has_one_attached :logo

  has_many :events, class_name: "Event", foreign_key: :venue_id, inverse_of: :venue_record, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validate :external_url_must_be_http_url
  validate :logo_must_be_image

  before_validation :normalize_attributes

  scope :ordered_by_name, -> { order(Arel.sql("LOWER(venues.name) ASC"), :id) }

  def self.normalize_name(value)
    normalized = value.to_s.strip
    return normalized unless normalized.match?(/kulturquartier/i)

    normalized.gsub(/\s*[-,]?\s*proton\b/i, "").strip
  end

  def self.same_name?(left, right)
    normalize_name(left).casecmp?(normalize_name(right))
  end

  def self.find_by_normalized_name(value)
    normalized = normalize_name(value)
    return if normalized.blank?

    where("LOWER(venues.name) = ?", normalized.downcase).first
  end

  def self.search_by_query(query, limit: 8)
    normalized_query = query.to_s.strip
    return none if normalized_query.blank?

    token = ActiveRecord::Base.sanitize_sql_like(normalized_query.downcase)
    prefix = "#{token}%"
    infix = "%#{token}%"
    order_sql = sanitize_sql_array(
      [
        <<~SQL.squish,
          CASE
            WHEN LOWER(venues.name) LIKE ? THEN 0
            WHEN LOWER(venues.name) LIKE ? THEN 1
            ELSE 2
          END,
          LOWER(venues.name) ASC,
          venues.id ASC
        SQL
        prefix,
        infix
      ]
    )

    where("LOWER(venues.name) LIKE ?", infix)
      .order(Arel.sql(order_sql))
      .limit(limit)
  end

  def self.filter_by_query(query)
    normalized_query = query.to_s.strip
    return all if normalized_query.blank?

    token = ActiveRecord::Base.sanitize_sql_like(normalized_query.downcase)
    prefix = "#{token}%"
    infix = "%#{token}%"
    order_sql = sanitize_sql_array(
      [
        <<~SQL.squish,
          CASE
            WHEN LOWER(venues.name) = ? THEN 0
            WHEN LOWER(venues.name) LIKE ? THEN 1
            WHEN LOWER(COALESCE(venues.address, '')) LIKE ? THEN 2
            ELSE 3
          END,
          LOWER(venues.name) ASC,
          venues.id ASC
        SQL
        token,
        prefix,
        prefix
      ]
    )

    where(
      <<~SQL.squish,
        LOWER(venues.name) LIKE :infix
        OR LOWER(COALESCE(venues.address, '')) LIKE :infix
        OR LOWER(COALESCE(venues.description, '')) LIKE :infix
        OR LOWER(COALESCE(venues.external_url, '')) LIKE :infix
      SQL
      infix:
    ).order(Arel.sql(order_sql))
  end

  def thumbnail_logo_variant
    processed_logo_representation(resize_to_limit: [ 160, 160 ])
  end

  def detail_logo_variant
    processed_logo_representation(resize_to_limit: [ 320, 320 ])
  end

  def events_count
    self[:events_count].to_i
  end

  def upcoming_events_count
    self[:upcoming_events_count].to_i
  end

  def to_s
    name.to_s
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
    Rails.logger.warn("Venue logo optimization fallback for ##{id || 'new'}: #{error.class}: #{error.message}")
    logo
  rescue ActiveStorage::InvariableError, ImageProcessing::Error => error
    raise ProcessingError, processing_error_message(error)
  rescue StandardError => error
    raise unless vips_processing_error?(error)

    raise ProcessingError, processing_error_message(error)
  end

  def normalize_attributes
    self.name = self.class.normalize_name(name)
    self.description = description.to_s.strip.presence
    self.external_url = external_url.to_s.strip.presence
    self.address = address.to_s.strip.presence
  end

  def external_url_must_be_http_url
    return if external_url.blank?

    uri = URI.parse(external_url)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:external_url, "muss mit http:// oder https:// beginnen")
  rescue URI::InvalidURIError
    errors.add(:external_url, "ist ungültig")
  end

  def logo_must_be_image
    return unless logo.attached?
    return if logo.content_type.to_s.start_with?("image/")

    errors.add(:logo, "muss ein Bild sein")
  end

  def processing_error_message(error)
    Rails.logger.warn("Venue logo optimization failed for ##{id || 'new'}: #{error.class}: #{error.message}")
    "Logo konnte nicht für die Anzeige optimiert werden."
  end

  def vips_processing_error?(error)
    defined?(Vips::Error) && error.is_a?(Vips::Error)
  end
end
