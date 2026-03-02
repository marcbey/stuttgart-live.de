class EventimImportEvent < ApplicationRecord
  belongs_to :import_source

  validates :external_event_id, :concert_date, :city, :venue_name, :title,
    :artist_name, :concert_date_label, :venue_label, :source_payload_hash,
    :first_seen_at, :last_seen_at, presence: true
  validates :is_active, inclusion: { in: [ true, false ] }
  validates :external_event_id, uniqueness: { scope: [ :import_source_id, :concert_date ] }

  before_validation :apply_defaults

  scope :active, -> { where(is_active: true) }

  private

  def apply_defaults
    self.is_active = true if is_active.nil?
    self.dump_payload = {} unless dump_payload.is_a?(Hash)
    self.detail_payload = {} unless detail_payload.is_a?(Hash)
  end
end
