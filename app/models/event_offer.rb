class EventOffer < ApplicationRecord
  belongs_to :event

  validates :source, :source_event_id, presence: true
  validates :source_event_id, uniqueness: { scope: [ :event_id, :source ] }
  validates :priority_rank, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :sold_out, inclusion: { in: [ true, false ] }

  before_validation :normalize_attributes

  scope :ordered, -> { order(priority_rank: :asc, id: :asc) }
  scope :active_ticket, -> { where(sold_out: false).where.not(ticket_url: [ nil, "" ]) }

  private

  def normalize_attributes
    self.source = source.to_s.strip
    self.source_event_id = source_event_id.to_s.strip
    self.ticket_url = ticket_url.to_s.strip.presence
    self.ticket_price_text = ticket_price_text.to_s.strip.presence
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
