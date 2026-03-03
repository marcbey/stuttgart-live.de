class Event < ApplicationRecord
  STATUSES = %w[imported needs_review ready_for_publish published rejected].freeze

  belongs_to :published_by, class_name: "User", optional: true

  has_many :event_offers, dependent: :destroy
  has_many :event_genres, dependent: :destroy
  has_many :genres, through: :event_genres
  has_many :event_change_logs, dependent: :destroy

  validates :slug, :title, :artist_name, :start_at, :venue, :city, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :slug, uniqueness: true
  validates :source_fingerprint, uniqueness: true, allow_nil: true
  validates :completeness_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, only_integer: true }

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

  private

  def normalize_attributes
    self.title = title.to_s.strip
    self.artist_name = artist_name.to_s.strip
    self.venue = venue.to_s.strip
    self.city = city.to_s.strip
    self.badge_text = badge_text.to_s.strip.presence
    self.image_url = image_url.to_s.strip.presence
    self.youtube_url = youtube_url.to_s.strip.presence
    self.primary_source = primary_source.to_s.strip.presence
    self.source_snapshot = {} unless source_snapshot.is_a?(Hash)
    self.completeness_flags = Array(completeness_flags).map(&:to_s)
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
