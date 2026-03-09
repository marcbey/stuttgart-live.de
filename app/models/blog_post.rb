class BlogPost < ApplicationRecord
  STATUSES = %w[draft published].freeze

  belongs_to :author, class_name: "User"
  belongs_to :published_by, class_name: "User", optional: true

  has_one_attached :cover_image
  has_rich_text :body

  validates :title, presence: true, length: { maximum: 180 }
  validates :teaser, presence: true, length: { maximum: 320 }
  validates :slug, presence: true, uniqueness: true
  validates :source_identifier, uniqueness: true, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :published_at, presence: true, if: :published?
  validate :body_must_be_present
  validate :cover_image_must_be_image

  before_validation :normalize_attributes
  before_validation :assign_slug, if: :slug_needed?

  scope :ordered_for_backend, -> { includes(:author, :published_by).with_attached_cover_image.order(updated_at: :desc, id: :desc) }
  scope :published_live, -> { where(status: "published").where("published_at <= ?", Time.current).order(published_at: :desc, id: :desc) }

  def self.find_live_by_source_path!(source_path)
    published_live.find_by!(source_url: source_url_candidates_for(source_path))
  end

  def published?
    status == "published"
  end

  def scheduled?
    published? && published_at.present? && published_at.future?
  end

  def live?
    published? && published_at.present? && published_at <= Time.current
  end

  def display_status
    return "Draft" unless published?
    return "Geplant" if scheduled?

    "Published"
  end

  def display_author_name
    author_name.to_s.strip.presence || author&.name.presence || author&.email_address.to_s
  end

  def self.source_url_candidates_for(source_path)
    normalized_path = normalize_source_path(source_path)
    return [] if normalized_path.blank?

    base_hosts = [
      "https://stuttgart-live.de",
      "https://www.stuttgart-live.de",
      "http://stuttgart-live.de",
      "http://www.stuttgart-live.de"
    ]

    [ normalized_path, "#{normalized_path}/" ] +
      base_hosts.flat_map do |host|
        [
          "#{host}#{normalized_path}",
          "#{host}#{normalized_path}/"
        ]
      end
  end

  def self.normalize_source_path(source_path)
    value = source_path.to_s.strip
    return if value.blank?

    path =
      if value.start_with?("http://", "https://")
        URI.parse(value).path
      else
        value
      end

    path = "/#{path}" unless path.start_with?("/")
    path.delete_suffix("/").presence || "/"
  rescue URI::InvalidURIError
    nil
  end

  private
    def normalize_attributes
      self.title = title.to_s.strip
      self.teaser = teaser.to_s.strip
      self.slug = slug.to_s.strip.parameterize.presence || slug
      self.author_name = author_name.to_s.strip.presence
      self.source_identifier = source_identifier.to_s.strip.presence
      self.source_url = source_url.to_s.strip.presence
      self.youtube_video_urls = Array(youtube_video_urls).filter_map { |value| normalize_youtube_url(value) }.uniq
    end

    def slug_needed?
      slug.blank?
    end

    def assign_slug
      base = title.to_s.parameterize
      base = "news" if base.blank?

      candidate = base
      suffix = 2

      while self.class.where.not(id: id).exists?(slug: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end

      self.slug = candidate
    end

    def body_must_be_present
      return if body.to_plain_text.strip.present?

      errors.add(:body, "muss ausgefüllt werden")
    end

    def cover_image_must_be_image
      return unless cover_image.attached?
      return if cover_image.content_type.to_s.start_with?("image/")

      errors.add(:cover_image, "muss ein Bild sein")
    end

    def normalize_youtube_url(value)
      url = value.to_s.strip
      return if url.blank?

      uri = URI.parse(url)
      host = uri.host.to_s.downcase

      if host.include?("youtu.be")
        video_id = uri.path.delete_prefix("/").split("/").first
      elsif host.include?("youtube.com") || host.include?("youtube-nocookie.com")
        if uri.path.include?("/embed/")
          video_id = uri.path.split("/embed/").last.to_s.split("/").first
        else
          video_id = CGI.parse(uri.query.to_s)["v"]&.first
        end
      end

      return if video_id.blank?

      "https://www.youtube.com/embed/#{video_id}"
    rescue URI::InvalidURIError
      nil
    end
end
