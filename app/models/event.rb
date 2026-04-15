class Event < ApplicationRecord
  STATUSES = %w[imported needs_review ready_for_publish published rejected].freeze
  EVENT_SERIES_ASSIGNMENTS = %w[auto manual manual_none].freeze
  DEFAULT_PROMOTION_BANNER_KICKER_TEXT = "Promotion"
  DEFAULT_PROMOTION_BANNER_CTA_TEXT = "Zum Event"
  DEFAULT_PROMOTION_BANNER_BACKGROUND_COLOR = "#E0F7F2"
  PROMOTION_BANNER_TEXT_COLOR_LIGHT = "light"
  PROMOTION_BANNER_TEXT_COLOR_DARK = "dark"
  HEX_COLOR_FORMAT = /\A#[0-9A-F]{6}\z/.freeze
  DEFAULT_IMAGE_FOCUS_X = EventImage::DEFAULT_CARD_FOCUS_X
  DEFAULT_IMAGE_FOCUS_Y = EventImage::DEFAULT_CARD_FOCUS_Y
  DEFAULT_IMAGE_ZOOM = EventImage::DEFAULT_CARD_ZOOM
  WEB_MAX_DIMENSION = EventImage::WEB_MAX_DIMENSION
  WEB_QUALITY = EventImage::WEB_QUALITY
  ProcessingError = Class.new(StandardError)
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
  belongs_to :event_series, optional: true
  belongs_to :venue_record, class_name: "Venue", foreign_key: :venue_id, inverse_of: :events, autosave: true, optional: true

  has_many :event_offers, dependent: :destroy
  has_many :event_genres, dependent: :destroy
  has_many :genres, through: :event_genres
  has_many :event_change_logs, dependent: :destroy
  has_many :event_images, dependent: :destroy
  has_many :event_presenters, -> { order(:position, :id) }, dependent: :destroy
  has_many :event_social_posts, -> { order(:platform, :id) }, dependent: :destroy
  has_many :presenters, -> { order("event_presenters.position ASC", "event_presenters.id ASC") }, through: :event_presenters
  has_one :llm_enrichment, class_name: "EventLlmEnrichment", dependent: :destroy
  has_one_attached :promotion_banner_image
  has_many :import_event_images,
    as: :import_event,
    foreign_key: :import_event_id,
    foreign_type: :import_class,
    dependent: :delete_all,
    inverse_of: :import_event

  attr_accessor :pending_promotion_banner_image_blob,
                :remove_promotion_banner_image,
                :venue_name,
                :validate_immediate_publication

  accepts_nested_attributes_for :llm_enrichment, update_only: true

  validates :slug, :title, :artist_name, :normalized_artist_name, :start_at, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :event_series_assignment, inclusion: { in: EVENT_SERIES_ASSIGNMENTS }
  validates :slug, uniqueness: true
  validates :source_fingerprint, uniqueness: true, allow_nil: true
  validates :completeness_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, only_integer: true }
  validates :min_price, :max_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :promotion_banner_kicker_text, length: { maximum: 80 }, allow_blank: true
  validates :promotion_banner_cta_text, length: { maximum: 80 }, allow_blank: true
  validates :promotion_banner_background_color, format: { with: HEX_COLOR_FORMAT }, allow_blank: true
  validates :promotion_banner_image_copyright, length: { maximum: 500 }, allow_blank: true
  validates :sks_sold_out_message, length: { maximum: 500 }, allow_blank: true
  validates :promotion_banner_image_focus_x, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :promotion_banner_image_focus_y, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :promotion_banner_image_zoom, numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 300 }
  validates :venue_record, presence: true
  validate :promotion_banner_image_must_be_image

  before_validation :normalize_attributes
  before_validation :assign_slug, if: :slug_needed?
  before_validation :apply_publication_schedule_rules
  before_save :clear_other_promotion_banners, if: :promotion_banner?
  validate :future_publication_must_not_be_published_immediately, if: :validate_immediate_publication?

  scope :chronological, -> { order(start_at: :asc, id: :asc) }
  scope :reverse_chronological, -> { order(start_at: :desc, id: :desc) }
  scope :by_status, ->(status) { where(status: status) }
  scope :published_live, lambda {
    where(status: "published")
      .where("published_at IS NULL OR published_at <= ?", Time.current)
      .chronological
  }
  scope :homepage_highlights, -> { where(promoter_id: sks_promoter_ids).or(where(highlighted: true)) }
  scope :highlighted_first, -> { reorder(Arel.sql("CASE WHEN events.highlighted = TRUE THEN 0 ELSE 1 END"), :start_at, :id) }
  scope :sks_first, -> { reorder(Arel.sql(sks_first_order_sql), :start_at, :id) }
  scope :search_priority_first, -> { reorder(Arel.sql(search_priority_order_sql), :start_at, :id) }
  scope :promotion_banner_live, lambda {
    published_live
      .where(promotion_banner: true)
      .includes(:venue_record, promotion_banner_image_attachment: :blob, event_images: [ file_attachment: :blob ])
  }

  def self.sks_promoter_ids
    AppSetting.sks_promoter_ids
  end

  def self.sks_first_order_sql
    quoted_ids = sks_promoter_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(", ")
    return "1" if quoted_ids.blank?

    "CASE WHEN events.promoter_id IN (#{quoted_ids}) THEN 0 ELSE 1 END"
  end

  def self.search_priority_order_sql
    quoted_ids = sks_promoter_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(", ")
    promoter_condition = quoted_ids.present? ? "events.promoter_id IN (#{quoted_ids}) OR " : ""

    "CASE WHEN #{promoter_condition}events.highlighted = TRUE THEN 0 ELSE 1 END"
  end

  def published?
    status == "published"
  end

  def needs_review?
    status == "needs_review"
  end

  def ready_for_publish?
    status == "ready_for_publish"
  end

  def rejected?
    status == "rejected"
  end

  def venue
    venue_name.to_s.presence || venue_record&.name.to_s.presence
  end

  def venue=(value)
    if value.is_a?(Venue)
      self.venue_record = value
      @venue_name = normalize_venue_name(value.name)
      return value
    end

    self.venue_name = normalize_venue_name(value)
    self.venue_record = Venues::Resolver.call(name: @venue_name, venue_id: venue_id)
  end

  def venue_name
    @venue_name.to_s.presence || venue_record&.name.to_s.presence
  end

  def venue_name=(value)
    @venue_name = normalize_venue_name(value)
    self.venue_record = Venues::Resolver.call(name: @venue_name, venue_id: venue_id)
  end

  def venue_description
    venue_record&.description.to_s.presence
  end

  def venue_external_url
    venue_record&.external_url.to_s.presence
  end

  def venue_address
    venue_record&.address.to_s.presence
  end

  def scheduled?
    ready_for_publish? && published_at.present? && published_at.future?
  end

  def live?
    published? && (published_at.blank? || published_at <= Time.current)
  end

  def past?
    start_at.present? && start_at < Time.current
  end

  def event_series?
    event_series_id.present?
  end

  def event_series_auto_assignment?
    event_series_assignment == "auto"
  end

  def event_series_manual_assignment?
    event_series_assignment == "manual"
  end

  def event_series_manually_excluded?
    event_series_assignment == "manual_none"
  end

  def event_series_locked_by_editor?
    event_series_manual_assignment? || event_series_manually_excluded?
  end

  def event_series_origin
    event_series&.origin.to_s.presence
  end

  def social_post_for(platform)
    if association(:event_social_posts).loaded?
      event_social_posts.find { |post| post.platform == platform.to_s }
    else
      event_social_posts.find_by(platform: platform.to_s)
    end
  end

  def social_publication_status
    posts = association(:event_social_posts).loaded? ? event_social_posts : event_social_posts.to_a
    return "draft" if posts.empty?

    published_count = posts.count(&:published?)
    failed_count = posts.count(&:failed?)

    return "partial" if published_count.positive? && failed_count.positive?
    return "published" if published_count == posts.size
    return "failed" if failed_count == posts.size
    return "publishing" if posts.any?(&:publishing?)
    return "approved" if posts.any?(&:approved?)

    "draft"
  end

  def sync_publication_fields(user: nil)
    self.published_by ||= user if published? && user.present?
    self.published_by = nil unless published?
  end

  def publish_now!(user:, auto_published: false)
    publish!(user:, auto_published:)
  end

  def publish!(user:, auto_published: false)
    self.status = "published"
    self.auto_published = auto_published
    self.published_by ||= user if user.present?
    self.validate_immediate_publication = true
    save!
  ensure
    self.validate_immediate_publication = false
  end

  def unpublish!(status: "ready_for_publish", auto_published: false)
    self.status = status
    self.auto_published = auto_published
    self.published_at = nil
    self.published_by = nil
    save!
  end

  private

  def apply_publication_schedule_rules
    return if validate_immediate_publication?
    return if published_at.blank?

    if published_at.future?
      return if rejected? || needs_review?

      self.status = "ready_for_publish"
      return
    end

    self.status = "published" if ready_for_publish?
  end

  def future_publication_must_not_be_published_immediately
    return unless published_at.present? && published_at.future?

    errors.add(:published_at, "liegt in der Zukunft und kann nicht sofort veröffentlicht werden.")
  end

  def validate_immediate_publication?
    ActiveModel::Type::Boolean.new.cast(@validate_immediate_publication)
  end

  public

  def primary_offer
    if association(:event_offers).loaded?
      return loaded_active_ticket_offers.min_by { |offer| [ offer.priority_rank.to_i, offer.id.to_i ] }
    end

    event_offers.active_ticket.ordered.first
  end

  def preferred_ticket_offer
    if association(:event_offers).loaded?
      return loaded_active_ticket_offers.min_by do |offer|
        [ offer.source.to_s.casecmp("easyticket").zero? ? 0 : 1, offer.priority_rank.to_i, offer.id.to_i ]
      end
    end

    event_offers
      .active_ticket
      .order(Arel.sql("CASE WHEN LOWER(source) = 'easyticket' THEN 0 ELSE 1 END"), :priority_rank, :id)
      .first
  end

  def imported_primary_ticket_offer
    if association(:event_offers).loaded?
      return loaded_imported_ticket_offers.min_by do |offer|
        [ offer_source_priority(offer.source), offer.priority_rank.to_i, offer.id.to_i ]
      end
    end

    event_offers
      .where.not(source: "manual")
      .order(Arel.sql(ticket_offer_source_priority_sql), :priority_rank, :id)
      .first
  end

  def manual_ticket_offer
    if association(:event_offers).loaded?
      return event_offers
        .select { |offer| offer.source.to_s == "manual" }
        .min_by { |offer| [ offer.priority_rank.to_i, offer.id.to_i ] }
    end

    event_offers.where(source: "manual").order(:priority_rank, :id).first
  end

  def editor_ticket_offer
    imported_primary_ticket_offer || manual_ticket_offer
  end

  def public_ticket_status_offer
    imported_primary_ticket_offer || manual_ticket_offer
  end

  def public_ticket_offer
    imported_offer = imported_primary_ticket_offer
    return imported_offer if ticket_offer_active?(imported_offer)
    return nil if imported_offer.present?

    manual_offer = manual_ticket_offer
    return manual_offer if ticket_offer_active?(manual_offer)

    nil
  end

  def public_canceled?
    public_ticket_status_offer&.canceled? == true
  end

  def public_sold_out?
    !public_canceled? && public_ticket_status_offer&.sold_out? == true
  end

  def public_ticket_status_label
    return "Abgesagt" if public_canceled?
    return "Ausverkauft" if public_sold_out?

    nil
  end

  def primary_genre
    if association(:genres).loaded?
      return genres.min_by { |genre| [ genre.name.to_s, genre.id.to_i ] }
    end

    genres.order(:name).first
  end

  def display_date
    I18n.l(start_at.to_date, format: "%d.%m.%Y")
  end

  def sks_promoter?
    self.class.sks_promoter_ids.include?(promoter_id.to_s)
  end

  def public_organizer_notes
    notes = organizer_notes.to_s.strip
    return notes if notes.present?
    return AppSetting.sks_organizer_notes if sks_promoter?

    nil
  end

  def show_public_organizer_notes?
    return false if public_organizer_notes.blank?

    show_organizer_notes? || sks_promoter?
  end

  def promotion_banner_kicker_text_value
    promotion_banner_kicker_text.presence || DEFAULT_PROMOTION_BANNER_KICKER_TEXT
  end

  def promotion_banner_cta_text_value
    promotion_banner_cta_text.presence || DEFAULT_PROMOTION_BANNER_CTA_TEXT
  end

  def promotion_banner_background_color_value
    promotion_banner_background_color.presence || DEFAULT_PROMOTION_BANNER_BACKGROUND_COLOR
  end

  def promotion_banner_text_color_scheme
    promotion_banner_background_bright? ? PROMOTION_BANNER_TEXT_COLOR_DARK : PROMOTION_BANNER_TEXT_COLOR_LIGHT
  end

  def promotion_banner_background_bright?
    red, green, blue = promotion_banner_background_color_value.delete_prefix("#").scan(/../).map { |channel| channel.to_i(16) }
    brightness = ((red * 299) + (green * 587) + (blue * 114)) / 1000.0

    brightness >= 160
  end

  def promotion_banner_image_blob_for_editor
    pending_blob = pending_promotion_banner_image_blob
    return pending_blob if pending_blob.present?
    return if remove_promotion_banner_image?

    promotion_banner_image.blob if promotion_banner_image.attached?
  end

  def remove_promotion_banner_image?
    ActiveModel::Type::Boolean.new.cast(remove_promotion_banner_image)
  end

  def promotion_banner_image_focus_x_value
    image_focus_value(promotion_banner_image_focus_x, fallback: DEFAULT_IMAGE_FOCUS_X)
  end

  def promotion_banner_image_focus_y_value
    image_focus_value(promotion_banner_image_focus_y, fallback: DEFAULT_IMAGE_FOCUS_Y)
  end

  def promotion_banner_image_zoom_value
    image_focus_value(promotion_banner_image_zoom, fallback: DEFAULT_IMAGE_ZOOM)
  end

  def promotion_banner_display_image_present?
    return true if promotion_banner_image.attached?

    if association(:event_images).loaded?
      event_images.any?
    else
      event_images.exists?
    end
  end

  def processed_optimized_promotion_banner_image_variant
    promotion_banner_image.variant(**variant_transformations).processed
  rescue LoadError => error
    Rails.logger.warn("Event promotion banner optimization fallback for ##{id || 'new'}: #{error.class}: #{error.message}")
    promotion_banner_image
  rescue MiniMagick::Error => error
    Rails.logger.warn("Event promotion banner optimization fallback for ##{id || 'new'}: #{error.class}: #{error.message}")
    promotion_banner_image
  rescue ActiveStorage::InvariableError, ImageProcessing::Error => error
    raise ProcessingError, processing_error_message(error)
  rescue StandardError => error
    raise unless vips_processing_error?(error)

    raise ProcessingError, processing_error_message(error)
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

    images =
      if association(:import_event_images).loaded?
        import_event_images.sort_by { |image| [ image.position.to_i, image.id.to_i ] }
      else
        import_event_images.ordered.to_a
      end
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

    PublicMediaUrl.path_for(image.processed_optimized_variant) ||
      Rails.application.routes.url_helpers.rails_storage_proxy_path(image.processed_optimized_variant, only_path: true)
  end

  def has_import_images?
    association = import_event_images
    association.loaded? ? association.any? : association.exists?
  end

  def ordered_presenters
    association = event_presenters

    if association.loaded?
      association
        .sort_by { |event_presenter| [ event_presenter.position.to_i, event_presenter.id.to_i ] }
        .filter_map(&:presenter)
    else
      presenters.to_a
    end
  end

  def slider_images
    if association(:event_images).loaded?
      return event_images.select(&:slider?).sort_by { |image| [ image.created_at || Time.at(0), image.id.to_i ] }
    end

    event_images.slider.ordered
  end

  def event_image
    if association(:event_images).loaded?
      ordered_images = event_images.sort_by { |image| [ image.created_at || Time.at(0), image.id.to_i ] }
      return ordered_images.find(&:detail_hero?) || ordered_images.first
    end

    event_images.detail_hero.ordered.first || event_images.ordered.first
  end

  private

  def loaded_active_ticket_offers
    event_offers.select do |offer|
      ticket_offer_active?(offer)
    end
  end

  def loaded_imported_ticket_offers
    event_offers.select { |offer| offer.source.to_s != "manual" }
  end

  def ticket_offer_active?(offer)
    offer.present? && !offer.sold_out? && !offer.canceled? && offer.ticket_url.present?
  end

  def offer_source_priority(source)
    provider_priority_map.fetch(source.to_s, 1_000)
  end

  def ticket_offer_source_priority_sql
    cases = provider_priority_map.sort_by { |source, rank| [ rank, source ] }.map do |source, rank|
      "WHEN #{ActiveRecord::Base.connection.quote(source)} THEN #{Integer(rank)}"
    end.join(" ")

    "CASE source #{cases} ELSE 1000 END"
  end

  def provider_priority_map
    @provider_priority_map ||= Merging::ProviderPriorityMap.call
  end

  def editorial_image_for(slot:, breakpoint:)
    detail_hero = event_image
    return detail_hero if detail_hero.present?

    nil
  end

  def normalize_attributes
    self.title = title.to_s.strip
    self.artist_name = artist_name.to_s.strip
    split_artist_and_tour_from_title!
    self.normalized_artist_name = Merging::ArtistNameNormalizer.normalize_with_fallback(artist_name, title)
    sync_venue_record
    normalized_city = city.to_s.strip
    self.city = normalized_city.casecmp("Unbekannt").zero? ? nil : normalized_city.presence
    self.badge_text = badge_text.to_s.strip.presence
    self.promotion_banner_kicker_text = promotion_banner_kicker_text.to_s.strip.presence
    self.promotion_banner_cta_text = promotion_banner_cta_text.to_s.strip.presence
    self.promotion_banner_background_color = normalize_hex_color(promotion_banner_background_color)
    self.promotion_banner_image_copyright = promotion_banner_image_copyright.to_s.strip.presence
    self.promotion_banner_image_focus_x = normalize_percentage(promotion_banner_image_focus_x, fallback: DEFAULT_IMAGE_FOCUS_X)
    self.promotion_banner_image_focus_y = normalize_percentage(promotion_banner_image_focus_y, fallback: DEFAULT_IMAGE_FOCUS_Y)
    self.promotion_banner_image_zoom = normalize_percentage(promotion_banner_image_zoom, fallback: DEFAULT_IMAGE_ZOOM)
    normalized_organizer_notes = organizer_notes.to_s.strip.presence
    self.organizer_notes = normalized_organizer_notes.presence || (sks_promoter? ? AppSetting.sks_organizer_notes : nil)
    self.homepage_url = homepage_url.to_s.strip.presence
    self.instagram_url = instagram_url.to_s.strip.presence
    self.facebook_url = facebook_url.to_s.strip.presence
    self.youtube_url = youtube_url.to_s.strip.presence
    self.sks_sold_out_message = sks_sold_out_message.to_s.strip.presence
    self.promoter_id = promoter_id.to_s.strip.presence
    self.promoter_name = promoter_name.to_s.strip.presence
    self.primary_source = primary_source.to_s.strip.presence
    self.event_series_assignment = event_series_assignment.to_s.strip.presence || "auto"
    self.source_snapshot = {} unless source_snapshot.is_a?(Hash)
    self.completeness_flags = Array(completeness_flags).map(&:to_s)

    self.min_price = nil if min_price.blank?
    self.max_price = nil if max_price.blank?
  end

  def clear_other_promotion_banners
    self.class.where.not(id: id).where(promotion_banner: true).update_all(promotion_banner: false, updated_at: Time.current)
  end

  def promotion_banner_image_must_be_image
    image_blob = promotion_banner_image_blob_for_editor
    return unless image_blob.present?
    return if image_blob.content_type.to_s.start_with?("image/")

    errors.add(:promotion_banner_image, "muss ein Bild sein")
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

  def normalize_hex_color(value)
    normalized = value.to_s.strip.upcase
    return if normalized.blank?

    normalized = "##{normalized}" unless normalized.start_with?("#")
    normalized
  end

  def image_focus_value(value, fallback:)
    normalized = value.to_f
    normalized.positive? ? normalized : fallback
  end

  def normalize_percentage(value, fallback:)
    return fallback if value.blank?

    value.to_f.round(2)
  end

  def variant_transformations
    transformations = {
      format: :webp,
      resize_to_limit: [ WEB_MAX_DIMENSION, WEB_MAX_DIMENSION ]
    }

    if ActiveStorage.variant_processor == :vips
      transformations[:saver] = {
        strip: true,
        quality: WEB_QUALITY
      }
    end

    transformations
  end

  def processing_error_message(error)
    Rails.logger.warn("Event promotion banner optimization failed for ##{id || 'new'}: #{error.class}: #{error.message}")
    "Bild konnte nicht für Web und Mobile optimiert werden."
  end

  def vips_processing_error?(error)
    defined?(Vips::Error) && error.is_a?(Vips::Error)
  end

  def normalize_comparison_token(value)
    value.to_s.downcase.gsub(/[^[:alnum:]]+/, "")
  end

  def normalize_venue_name(value)
    Venue.normalize_name(value)
  end

  def sync_venue_record
    resolved_venue = Venues::Resolver.call(name: @venue_name, venue_id: venue_id)
    self.venue_record = resolved_venue
    self.venue_name = resolved_venue&.name || @venue_name
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
