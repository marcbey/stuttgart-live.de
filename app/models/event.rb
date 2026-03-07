class Event < ApplicationRecord
  STATUSES = %w[imported needs_review ready_for_publish published rejected].freeze
  IMAGE_SLOT_PREFERENCES = {
    [ :grid_default, :desktop ] => [
      [ "cover", %w[landscape square portrait unknown] ],
      [ "gallery", %w[landscape square portrait unknown] ],
      [ "thumb", %w[square landscape portrait unknown] ]
    ],
    [ :grid_tall, :desktop ] => [
      [ "cover", %w[portrait square landscape unknown] ],
      [ "gallery", %w[portrait square landscape unknown] ],
      [ "thumb", %w[portrait square landscape unknown] ]
    ],
    [ :grid_default, :mobile ] => [
      [ "cover", %w[square landscape portrait unknown] ],
      [ "gallery", %w[square landscape portrait unknown] ],
      [ "thumb", %w[square landscape portrait unknown] ]
    ],
    [ :detail_hero, :desktop ] => [
      [ "cover", %w[landscape portrait square unknown] ],
      [ "gallery", %w[landscape portrait square unknown] ],
      [ "thumb", %w[landscape square portrait unknown] ]
    ],
    [ :social_card, :desktop ] => [
      [ "cover", %w[landscape square portrait unknown] ],
      [ "gallery", %w[landscape square portrait unknown] ],
      [ "thumb", %w[square landscape portrait unknown] ]
    ]
  }.freeze
  GRID_VARIANT_BY_SLOT = {
    grid_default: EventImage::GRID_VARIANT_1X1,
    grid_tall: EventImage::GRID_VARIANT_1X2,
    grid_wide: EventImage::GRID_VARIANT_2X1,
    grid_large: EventImage::GRID_VARIANT_2X2
  }.freeze

  belongs_to :published_by, class_name: "User", optional: true

  has_many :event_offers, dependent: :destroy
  has_many :event_genres, dependent: :destroy
  has_many :genres, through: :event_genres
  has_many :event_change_logs, dependent: :destroy
  has_many :event_images, dependent: :destroy
  has_many :import_event_images,
    as: :import_event,
    foreign_key: :import_event_id,
    foreign_type: :import_class,
    dependent: :delete_all,
    inverse_of: :import_event

  validates :slug, :title, :artist_name, :start_at, :venue, :city, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :slug, uniqueness: true
  validates :source_fingerprint, uniqueness: true, allow_nil: true
  validates :completeness_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, only_integer: true }
  validates :min_price, :max_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :normalize_attributes
  before_validation :assign_slug, if: :slug_needed?

  scope :chronological, -> { order(start_at: :asc, id: :asc) }
  scope :reverse_chronological, -> { order(start_at: :desc, id: :desc) }
  scope :by_status, ->(status) { where(status: status) }
  scope :published_live, -> { where(status: "published").where("published_at <= ?", Time.current).chronological }

  def published?
    status == "published"
  end

  def primary_offer
    event_offers.active_ticket.ordered.first
  end

  def preferred_ticket_offer
    event_offers
      .active_ticket
      .order(Arel.sql("CASE WHEN LOWER(source) = 'easyticket' THEN 0 ELSE 1 END"), :priority_rank, :id)
      .first
  end

  def primary_genre
    genres.order(:name).first
  end

  def display_date
    I18n.l(start_at.to_date, format: "%d.%m.%Y")
  end

  def youtube_embed_url
    return "" if youtube_url.blank?

    id = extract_youtube_id(youtube_url)
    return "" if id.blank?

    "https://www.youtube.com/embed/#{id}"
  end

  def image_for(slot: :grid_default, breakpoint: :desktop)
    editorial = editorial_image_for(slot: slot, breakpoint: breakpoint)
    return editorial if editorial.present?

    images = import_event_images.ordered.to_a
    return nil if images.empty?

    preferences = IMAGE_SLOT_PREFERENCES.fetch([ slot.to_sym, breakpoint.to_sym ], IMAGE_SLOT_PREFERENCES[[ :grid_default, :desktop ]])

    preferences.each do |role, aspect_hints|
      image = images.find do |candidate|
        candidate.role == role && aspect_hints.include?(candidate.aspect_hint)
      end
      return image if image.present?
    end

    images.first
  end

  def image_url_for(slot: :grid_default, breakpoint: :desktop)
    image = image_for(slot: slot, breakpoint: breakpoint)
    return nil if image.blank?
    return image.image_url unless image.is_a?(EventImage)
    return nil unless image.file.attached?

    Rails.application.routes.url_helpers.rails_storage_proxy_path(image.file, only_path: true)
  end

  def has_import_images?
    association = import_event_images
    association.loaded? ? association.any? : association.exists?
  end

  def slider_images
    event_images.slider.ordered
  end

  private

  def editorial_image_for(slot:, breakpoint:)
    normalized_slot = slot.to_sym
    normalized_breakpoint = breakpoint.to_sym

    if normalized_slot == :detail_hero
      detail_hero = event_images.detail_hero.ordered.first
      return detail_hero if detail_hero.present?

      grid_default = event_images.grid_tile.where(grid_variant: EventImage::GRID_VARIANT_1X1).ordered.first
      return grid_default if grid_default.present?

      return event_images.grid_tile.ordered.first
    end

    if normalized_slot == :social_card
      detail_hero = event_images.detail_hero.ordered.first
      return detail_hero if detail_hero.present?
    end

    if normalized_breakpoint == :mobile
      grid_default = event_images.grid_tile.where(grid_variant: EventImage::GRID_VARIANT_1X1).ordered.first
      return grid_default if grid_default.present?
    end

    grid_variant = GRID_VARIANT_BY_SLOT[normalized_slot]
    return nil if grid_variant.blank?

    event_images.grid_tile.where(grid_variant: grid_variant).ordered.first
  end

  def normalize_attributes
    self.title = title.to_s.strip
    self.artist_name = artist_name.to_s.strip
    split_artist_and_tour_from_title!
    self.venue = normalize_venue_name(venue)
    self.city = city.to_s.strip
    self.badge_text = badge_text.to_s.strip.presence
    self.organizer_notes = organizer_notes.to_s.strip.presence
    self.homepage_url = homepage_url.to_s.strip.presence
    self.instagram_url = instagram_url.to_s.strip.presence
    self.facebook_url = facebook_url.to_s.strip.presence
    self.youtube_url = youtube_url.to_s.strip.presence
    self.promoter_id = promoter_id.to_s.strip.presence
    self.primary_source = primary_source.to_s.strip.presence
    self.source_snapshot = {} unless source_snapshot.is_a?(Hash)
    self.completeness_flags = Array(completeness_flags).map(&:to_s)

    self.min_price = nil if min_price.blank?
    self.max_price = nil if max_price.blank?
  end

  def split_artist_and_tour_from_title!
    return if title.blank?

    match = title.match(/\A(.+?)\s*[-–—]\s+(.+)\z/)
    return unless match

    extracted_artist = match[1].to_s.strip
    extracted_title = match[2].to_s.strip
    return if extracted_artist.blank? || extracted_title.blank?

    normalized_artist = normalize_comparison_token(artist_name)
    normalized_title = normalize_comparison_token(title)
    normalized_extracted_artist = normalize_comparison_token(extracted_artist)

    if artist_name.blank? || normalized_artist == normalized_title || normalized_artist == normalized_extracted_artist
      self.artist_name = extracted_artist
      self.title = extracted_title
    end
  end

  def slug_needed?
    slug.blank?
  end

  def assign_slug
    base = [ artist_name.presence || title, start_at&.to_date ].compact.join("-").parameterize
    base = "event" if base.blank?

    candidate = base
    suffix = 2
    while self.class.where.not(id: id).exists?(slug: candidate)
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end

    self.slug = candidate
  end

  def normalize_comparison_token(value)
    value.to_s.downcase.gsub(/[^[:alnum:]]+/, "")
  end

  def normalize_venue_name(value)
    normalized = value.to_s.strip
    return normalized unless normalized.match?(/kulturquartier/i)

    normalized.gsub(/\s*[-,]?\s*proton\b/i, "").strip
  end

  def extract_youtube_id(url)
    uri = URI.parse(url)

    if uri.host&.include?("youtu.be")
      return uri.path.delete_prefix("/")
    end

    if uri.host&.include?("youtube.com")
      query = Rack::Utils.parse_query(uri.query)
      return query["v"] if query["v"].present?

      parts = uri.path.split("/")
      idx = parts.index("embed")
      return parts[idx + 1] if idx && parts[idx + 1].present?
    end

    ""
  rescue URI::InvalidURIError
    ""
  end
end
