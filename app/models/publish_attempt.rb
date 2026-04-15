class PublishAttempt < ApplicationRecord
  STATUSES = %w[started succeeded failed].freeze

  belongs_to :event_social_post
  belongs_to :social_connection, optional: true
  belongs_to :social_connection_target, optional: true
  belongs_to :initiated_by, class_name: "User", optional: true

  validates :platform, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  before_validation :normalize_attributes

  def succeed!(response_snapshot:)
    update!(
      status: "succeeded",
      finished_at: Time.current,
      error_code: nil,
      error_message: nil,
      response_snapshot: response_snapshot
    )
  end

  def fail!(message:, error_code: nil, response_snapshot: {})
    update!(
      status: "failed",
      finished_at: Time.current,
      error_code: error_code.to_s.strip.presence,
      error_message: message.to_s.strip.presence,
      response_snapshot: response_snapshot
    )
  end

  private

  def normalize_attributes
    self.platform = platform.to_s.strip
    self.status = status.to_s.strip.presence || "started"
    self.error_code = error_code.to_s.strip.presence
    self.error_message = error_message.to_s.strip.presence
    self.request_snapshot = {} unless request_snapshot.is_a?(Hash)
    self.response_snapshot = {} unless response_snapshot.is_a?(Hash)
    self.started_at ||= Time.current
  end
end
