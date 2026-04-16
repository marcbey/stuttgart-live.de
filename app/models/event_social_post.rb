class EventSocialPost < ApplicationRecord
  CANONICAL_PLATFORM = "instagram".freeze
  PLATFORMS = %w[facebook instagram].freeze
  ACTIVE_PLATFORMS = [ CANONICAL_PLATFORM ].freeze
  STATUSES = %w[draft approved publishing published failed].freeze

  belongs_to :event
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :published_by, class_name: "User", optional: true
  has_many :publish_attempts, dependent: :destroy
  has_one_attached :preview_image
  has_one_attached :publish_image_facebook
  has_one_attached :publish_image_instagram

  validates :platform, presence: true, inclusion: { in: PLATFORMS }, uniqueness: { scope: :event_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :caption, presence: true

  before_validation :normalize_attributes
  attr_writer :card_artist_name, :card_meta_line

  scope :ordered, -> { order(:platform, :id) }

  def self.platforms_for_select
    ACTIVE_PLATFORMS
  end

  def draft?
    status == "draft"
  end

  def approved?
    status == "approved"
  end

  def publishing?
    status == "publishing"
  end

  def published?
    status == "published"
  end

  def failed?
    status == "failed"
  end

  def caption_editable?
    !published? && !publishing?
  end

  def card_artist_name
    @card_artist_name.presence ||
      payload_snapshot.dig("card_text", "artist_name").to_s.strip.presence ||
      event.artist_name.to_s.strip
  end

  def card_meta_line
    @card_meta_line.presence ||
      payload_snapshot.dig("card_text", "meta_line").to_s.strip.presence ||
      default_card_meta_line
  end

  def card_payload
    {
      artist_name: card_artist_name,
      meta_line: card_meta_line
    }
  end

  def preview_image_url
    publish_image_instagram_url.presence || asset_url_for(preview_image)
  end

  def publish_image_facebook_url
    asset_url_for(publish_image_facebook)
  end

  def publish_image_instagram_url
    asset_url_for(publish_image_instagram)
  end

  def facebook_post_url
    return unless platform == "facebook"

    page_id, post_id = remote_post_id.to_s.split("_", 2)
    return if page_id.blank? || post_id.blank?

    "https://www.facebook.com/#{page_id}/posts/#{post_id}"
  end

  def instagram_post_url
    return unless platform == "instagram"

    payload_snapshot.dig("media", "permalink").to_s.strip.presence ||
      payload_snapshot.dig("publish", "permalink").to_s.strip.presence ||
      payload_snapshot.dig("publish_response", "permalink").to_s.strip.presence
  end

  def published_post_url
    case platform
    when "facebook"
      facebook_post_url
    when "instagram"
      instagram_post_url
    end
  end

  def publish_image_url_for(target_platform = platform)
    case target_platform.to_s
    when "facebook"
      publish_image_instagram_url.presence || publish_image_facebook_url.presence || image_url
    when "instagram"
      publish_image_instagram_url.presence || image_url
    else
      publish_image_instagram_url.presence || image_url
    end
  end

  def ready_for_publish?
    draft? || approved? || publishing? || failed?
  end

  def approval_errors
    errors = []
    target_url_valid = valid_http_url?(target_url)
    publish_image_url = publish_image_url_for(platform)
    image_url_valid = valid_http_url?(publish_image_url)

    errors << "Event-Link fehlt oder ist ungültig." unless target_url_valid
    errors << "Bild-Link fehlt oder ist ungültig." unless image_url_valid
    errors << "Event-Link ist nicht öffentlich erreichbar." if target_url_valid && !Meta::PublicUrlGuard.public_url?(target_url)
    errors << "Bild-Link ist nicht öffentlich erreichbar." if image_url_valid && !Meta::PublicUrlGuard.public_url?(publish_image_url)
    errors
  end

  def publish_errors
    errors = approval_errors
    errors << "Post ist bereits veröffentlicht." if published?
    errors << "Event ist noch nicht öffentlich live." unless event.live?
    errors
  end

  def ensure_approvable!
    messages = approval_errors
    raise Meta::Error, messages.to_sentence if messages.any?
  end

  def ensure_publishable!
    messages = publish_errors
    raise Meta::Error, messages.to_sentence if messages.any?
  end

  def approve!(user:)
    ensure_approvable!
    update!(
      status: "approved",
      approved_at: Time.current,
      approved_by: user,
      error_message: nil
    )
  end

  def assign_draft_attributes!(attributes)
    assign_attributes(
      attributes.merge(
        status: "draft",
        approved_at: nil,
        approved_by: nil,
        published_at: nil,
        published_by: nil,
        remote_media_id: nil,
        remote_post_id: nil,
        error_message: nil
      )
    )
  end

  def reset_workflow_to_draft!
    assign_attributes(
      status: "draft",
      approved_at: nil,
      approved_by: nil,
      published_at: nil,
      published_by: nil,
      remote_media_id: nil,
      remote_post_id: nil,
      error_message: nil
    )
  end

  def mark_publishing!
    update!(status: "publishing", error_message: nil)
  end

  def queued_for_publish?
    publishing?
  end

  def mark_published!(user:, remote_media_id:, remote_post_id:, payload: nil)
    update!(
      status: "published",
      published_at: Time.current,
      published_by: user,
      remote_media_id: remote_media_id,
      remote_post_id: remote_post_id,
      error_message: nil,
      payload_snapshot: merged_payload_snapshot(payload)
    )
  end

  def mark_failed!(message, payload: nil)
    update!(
      status: "failed",
      error_message: message,
      payload_snapshot: merged_payload_snapshot(payload)
    )
  end

  private

  def normalize_attributes
    self.platform = platform.to_s.strip
    self.status = status.to_s.strip.presence || "draft"
    self.caption = caption.to_s.strip
    self.target_url = target_url.to_s.strip.presence
    self.image_url = image_url.to_s.strip.presence
    self.remote_media_id = remote_media_id.to_s.strip.presence
    self.remote_post_id = remote_post_id.to_s.strip.presence
    self.error_message = error_message.to_s.strip.presence
    self.payload_snapshot = {} unless payload_snapshot.is_a?(Hash)
    payload_snapshot["card_text"] = {
      "artist_name" => card_artist_name.to_s.strip,
      "meta_line" => card_meta_line.to_s.strip
    }
  end

  def valid_http_url?(value)
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def merged_payload_snapshot(payload)
    return payload_snapshot if payload.blank?

    payload_snapshot.deep_merge(payload.deep_stringify_keys)
  end

  def asset_url_for(attachment)
    return unless attachment.attached?

    Meta::PublicAssetUrl.url_for(attachment)
  end

  def default_card_meta_line
    [
      event.start_at.present? ? I18n.l(event.start_at.to_date, format: "%d.%m.%Y") : nil,
      event.venue.to_s.strip.presence
    ].compact.join(" · ").presence.to_s
  end
end
