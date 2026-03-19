class BlogPost < ApplicationRecord
  STATUSES = %w[draft published].freeze
  DEFAULT_IMAGE_FOCUS_X = 50.0
  DEFAULT_IMAGE_FOCUS_Y = 50.0
  DEFAULT_IMAGE_ZOOM = 100.0
  WEB_MAX_DIMENSION = 1280
  WEB_QUALITY = 82
  IMAGE_SLOTS = %i[cover_image promotion_banner_image].freeze
  ProcessingError = Class.new(StandardError)

  belongs_to :author, class_name: "User"
  belongs_to :published_by, class_name: "User", optional: true

  has_one_attached :cover_image
  has_one_attached :promotion_banner_image
  has_rich_text :body

  attr_accessor :pending_cover_image_blob,
                :pending_promotion_banner_image_blob,
                :remove_cover_image,
                :remove_promotion_banner_image

  validates :title, presence: true, length: { maximum: 180 }
  validates :teaser, presence: true, length: { maximum: 320 }
  validates :slug, presence: true, uniqueness: true
  validates :source_identifier, uniqueness: true, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :published_at, presence: true, if: :published?
  validates :cover_image_copyright, length: { maximum: 500 }, allow_blank: true
  validates :promotion_banner_image_copyright, length: { maximum: 500 }, allow_blank: true
  validates :cover_image_focus_x, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :cover_image_focus_y, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :cover_image_zoom, numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 300 }
  validates :promotion_banner_image_focus_x, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :promotion_banner_image_focus_y, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :promotion_banner_image_zoom, numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 300 }
  validate :body_must_be_present
  validate :cover_image_must_be_image
  validate :promotion_banner_image_must_be_image
  validate :promotion_banner_requires_image

  before_validation :normalize_attributes
  before_validation :assign_slug, if: :slug_needed?
  before_save :clear_other_promotion_banners, if: :promotion_banner?

  scope :ordered_for_backend, -> { includes(:author, :published_by).with_attached_cover_image.with_attached_promotion_banner_image.order(updated_at: :desc, id: :desc) }
  scope :published_live, -> { where(status: "published").where("published_at <= ?", Time.current).order(published_at: :desc, id: :desc) }
  scope :promotion_banner_live, -> { published_live.where(promotion_banner: true).with_attached_promotion_banner_image }

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

  def cover_image_blob_for_editor
    image_blob_for_editor(:cover_image)
  end

  def promotion_banner_image_blob_for_editor
    image_blob_for_editor(:promotion_banner_image)
  end

  def remove_cover_image?
    ActiveModel::Type::Boolean.new.cast(remove_cover_image)
  end

  def remove_promotion_banner_image?
    ActiveModel::Type::Boolean.new.cast(remove_promotion_banner_image)
  end

  def cover_image_focus_x_value
    image_focus_value(cover_image_focus_x, fallback: DEFAULT_IMAGE_FOCUS_X)
  end

  def cover_image_focus_y_value
    image_focus_value(cover_image_focus_y, fallback: DEFAULT_IMAGE_FOCUS_Y)
  end

  def cover_image_zoom_value
    image_focus_value(cover_image_zoom, fallback: DEFAULT_IMAGE_ZOOM)
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

  def optimized_image_variant(slot)
    attachment_for_slot(slot).variant(
      format: :webp,
      saver: {
        strip: true,
        quality: WEB_QUALITY
      },
      resize_to_limit: [ WEB_MAX_DIMENSION, WEB_MAX_DIMENSION ]
    )
  end

  def processed_optimized_image_variant(slot)
    optimized_image_variant(slot).processed
  rescue ActiveStorage::InvariableError, ImageProcessing::Error => error
    raise ProcessingError, processing_error_message(slot, error)
  rescue StandardError => error
    raise unless vips_processing_error?(error)

    raise ProcessingError, processing_error_message(slot, error)
  end

  def apply_publication_action(action:, user:)
    case action.to_s
    when "publish"
      self.status = "published"
      self.published_at ||= Time.current
      self.published_by = user
    when "depublish"
      self.status = "draft"
      self.published_at = nil
      self.published_by = nil
    else
      self.status ||= "draft"
      self.published_by = nil if status == "draft"
    end
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
      self.cover_image_copyright = cover_image_copyright.to_s.strip.presence
      self.promotion_banner_image_copyright = promotion_banner_image_copyright.to_s.strip.presence
      self.cover_image_focus_x = normalize_percentage(cover_image_focus_x, fallback: DEFAULT_IMAGE_FOCUS_X)
      self.cover_image_focus_y = normalize_percentage(cover_image_focus_y, fallback: DEFAULT_IMAGE_FOCUS_Y)
      self.cover_image_zoom = normalize_percentage(cover_image_zoom, fallback: DEFAULT_IMAGE_ZOOM)
      self.promotion_banner_image_focus_x = normalize_percentage(promotion_banner_image_focus_x, fallback: DEFAULT_IMAGE_FOCUS_X)
      self.promotion_banner_image_focus_y = normalize_percentage(promotion_banner_image_focus_y, fallback: DEFAULT_IMAGE_FOCUS_Y)
      self.promotion_banner_image_zoom = normalize_percentage(promotion_banner_image_zoom, fallback: DEFAULT_IMAGE_ZOOM)
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
      image_blob = cover_image_blob_for_editor
      return unless image_blob.present?
      return if image_blob.content_type.to_s.start_with?("image/")

      errors.add(:cover_image, "muss ein Bild sein")
    end

    def promotion_banner_image_must_be_image
      image_blob = promotion_banner_image_blob_for_editor
      return unless image_blob.present?
      return if image_blob.content_type.to_s.start_with?("image/")

      errors.add(:promotion_banner_image, "muss ein Bild sein")
    end

    def promotion_banner_requires_image
      return unless promotion_banner?
      return if promotion_banner_image_blob_for_editor.present?

      errors.add(:promotion_banner_image, "muss für einen Promotion Banner vorhanden sein")
    end

    def clear_other_promotion_banners
      self.class.where.not(id: id).where(promotion_banner: true).update_all(promotion_banner: false, updated_at: Time.current)
    end

    def image_blob_for_editor(slot)
      pending_blob = pending_blob_for(slot)
      return pending_blob if pending_blob.present?
      return if remove_image_for(slot)

      attachment = public_send(slot)
      attachment.blob if attachment.attached?
    end

    def pending_blob_for(slot)
      case slot
      when :cover_image
        pending_cover_image_blob
      when :promotion_banner_image
        pending_promotion_banner_image_blob
      end
    end

    def remove_image_for(slot)
      case slot
      when :cover_image
        remove_cover_image?
      when :promotion_banner_image
        remove_promotion_banner_image?
      else
        false
      end
    end

    def image_focus_value(value, fallback:)
      normalized = value.to_f
      normalized.positive? ? normalized : fallback
    end

    def normalize_percentage(value, fallback:)
      return fallback if value.blank?

      value.to_f.round(2)
    end

    def attachment_for_slot(slot)
      normalized_slot = slot.to_sym
      raise ArgumentError, "unsupported image slot: #{slot}" unless IMAGE_SLOTS.include?(normalized_slot)

      attachment = public_send(normalized_slot)
      raise ArgumentError, "missing image attachment for #{normalized_slot}" unless attachment.attached?

      attachment
    end

    def processing_error_message(slot, error)
      Rails.logger.warn("BlogPost image optimization failed for ##{id || 'new'} (#{slot}): #{error.class}: #{error.message}")
      "Bild konnte nicht für Web und Mobile optimiert werden."
    end

    def vips_processing_error?(error)
      defined?(Vips::Error) && error.is_a?(Vips::Error)
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
