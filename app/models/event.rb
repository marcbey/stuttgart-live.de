class Event < ApplicationRecord
  STATUSES = %w[imported needs_review ready_for_publish published rejected].freeze
  SKS_PROMOTER_IDS = %w[10135 10136 382].freeze
  DEFAULT_SKS_ORGANIZER_NOTES = <<~TEXT.strip
    Wir bitten um Beachtung verstärkter Sicherheitsmaßnahmen
    Verbot von Handtaschen, Rucksäcken und Helmen
    Zusätzliche verschärfte Kontrollen und Bodychecks
    Sämtliche Besucher werden Bodychecks unterzogen. Taschen, Rucksäcke und Handtaschen sowie Helme und Behältnisse aller Art sind verboten.
    Die Zuschauer werden ausdrücklich gebeten, auf deren Mitbringen zu verzichten, und sich ausschließlich auf wirklich notwendige Utensilien wie Handys, Schlüsselbund und Portemonnaies sowie Medikamente oder Kosmetika in Gürteltaschen oder Kosmetiktäschchen bis zu einer maximalen Größe von Din A4 zu beschränken.
    Die Einhaltung dieser Regeln und Hinweise sowie ein rechtzeitiges Eintreffen helfen dabei, den Einlass so zügig wie möglich zu organisieren.

    Wir danken für Ihr Verständnis!

    Altersfreigabe:
    kein Zutritt: unter 6 Jahren
    nur in Begleitung: bis 14 Jahren (Das Begleitformular findest Du HIER)
    frei ab 14 Jahren

    Telefonischer Ticketkauf:

    Bei dieser Veranstaltung gibt es auch die Möglichkeit des telefonischen Ticketkaufes. Sie erreichen unsere Tickethotline in der Regel von Montag bis Freitag zwischen 10 und 18 Uhr unter Telefon 0711-550 660 77
  TEXT
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

  validates :slug, :title, :artist_name, :start_at, :venue, :status, presence: true
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

  def sync_publication_fields(user: nil)
    if published?
      self.published_at ||= Time.current
      self.published_by ||= user if user.present?
    else
      self.published_at = nil
      self.published_by = nil
    end
  end

  def publish_now!(user:, auto_published: false)
    self.status = "published"
    self.auto_published = auto_published
    self.published_at = Time.current
    self.published_by = user
    save!
  end

  def unpublish!(status: "ready_for_publish", auto_published: false)
    self.status = status
    self.auto_published = auto_published
    self.published_at = nil
    self.published_by = nil
    save!
  end

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
    SKS_PROMOTER_IDS.include?(promoter_id.to_s)
  end

  def public_organizer_notes
    notes = organizer_notes.to_s.strip
    return notes if notes.present?
    return DEFAULT_SKS_ORGANIZER_NOTES if sks_promoter?

    nil
  end

  def show_public_organizer_notes?
    return false if public_organizer_notes.blank?

    show_organizer_notes? || sks_promoter?
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

    Rails.application.routes.url_helpers.rails_storage_proxy_path(image.file, only_path: true)
  end

  def has_import_images?
    association = import_event_images
    association.loaded? ? association.any? : association.exists?
  end

  def slider_images
    if association(:event_images).loaded?
      return event_images.select(&:slider?).sort_by { |image| [ image.created_at || Time.at(0), image.id.to_i ] }
    end

    event_images.slider.ordered
  end

  def event_image
    if association(:event_images).loaded?
      return event_images
        .select(&:detail_hero?)
        .min_by { |image| [ image.created_at || Time.at(0), image.id.to_i ] }
    end

    event_images.detail_hero.ordered.first
  end

  private

  def loaded_active_ticket_offers
    event_offers.select do |offer|
      !offer.sold_out? && offer.ticket_url.present?
    end
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
    self.venue = normalize_venue_name(venue)
    normalized_city = city.to_s.strip
    self.city = normalized_city.casecmp("Unbekannt").zero? ? nil : normalized_city.presence
    self.badge_text = badge_text.to_s.strip.presence
    normalized_organizer_notes = organizer_notes.to_s.strip.presence
    self.organizer_notes = normalized_organizer_notes.presence || (sks_promoter? ? DEFAULT_SKS_ORGANIZER_NOTES : nil)
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
