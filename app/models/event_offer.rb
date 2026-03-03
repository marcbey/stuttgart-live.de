class EventOffer < ApplicationRecord
  EVENT_ID_TEMPLATE_PLACEHOLDERS = [ "%{event_id}", "{event_id}" ].freeze

  belongs_to :event

  validates :source, :source_event_id, presence: true
  validates :source_event_id, uniqueness: { scope: [ :event_id, :source ] }
  validates :priority_rank, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :sold_out, inclusion: { in: [ true, false ] }

  before_validation :normalize_attributes

  scope :ordered, -> { order(priority_rank: :asc, id: :asc) }
  scope :active_ticket, -> { where(sold_out: false).where.not(ticket_url: [ nil, "" ]) }

  def resolved_ticket_url
    self.class.resolve_ticket_url(ticket_url, source_event_id)
  end

  def self.resolve_ticket_url(url, source_event_id)
    normalized_url = url.to_s.strip
    return "" if normalized_url.blank?
    normalized_source_event_id = source_event_id.to_s.strip
    return normalized_url if normalized_source_event_id.blank?

    resolved_url =
      EVENT_ID_TEMPLATE_PLACEHOLDERS.reduce(normalized_url) do |memo, placeholder|
        memo.gsub(placeholder, normalized_source_event_id)
      end

    # Prevent duplicated trailing event IDs like /123/123.
    duplicate_pattern = %r{/#{Regexp.escape(normalized_source_event_id)}/#{Regexp.escape(normalized_source_event_id)}(?=/|\z)}
    resolved_url.sub(duplicate_pattern, "/#{normalized_source_event_id}")
  end

  private

  def normalize_attributes
    self.source = source.to_s.strip
    self.source_event_id = source_event_id.to_s.strip
    self.ticket_url = ticket_url.to_s.strip.presence
    self.ticket_price_text = ticket_price_text.to_s.strip.presence
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
