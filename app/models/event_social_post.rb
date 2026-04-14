class EventSocialPost < ApplicationRecord
  PLATFORMS = %w[facebook instagram].freeze
  STATUSES = %w[draft approved publishing published failed].freeze

  belongs_to :event
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :published_by, class_name: "User", optional: true

  validates :platform, presence: true, inclusion: { in: PLATFORMS }, uniqueness: { scope: :event_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :caption, presence: true

  before_validation :normalize_attributes

  scope :ordered, -> { order(:platform, :id) }

  def self.platforms_for_select
    PLATFORMS
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

  def ready_for_publish?
    approved? || (failed? && approved_at.present?)
  end

  def approval_errors
    errors = []
    errors << "Event-Link fehlt oder ist ungültig." unless valid_http_url?(target_url)
    errors << "Bild-Link fehlt oder ist ungültig." unless valid_http_url?(image_url)
    errors
  end

  def publish_errors
    errors = approval_errors
    errors << "Post muss zuerst freigegeben werden." unless ready_for_publish?
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
end
