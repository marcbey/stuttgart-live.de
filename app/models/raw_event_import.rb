class RawEventImport < ApplicationRecord
  belongs_to :import_source

  validates :import_event_type, presence: true, inclusion: { in: ImportSource::SOURCE_TYPES }
  validates :source_identifier, presence: true
  validate :payload_must_be_hash
  validate :detail_payload_must_be_hash

  before_validation :normalize_attributes

  scope :chronological, -> { order(created_at: :asc, id: :asc) }

  def self.latest_for(relation = all)
    relation.chronological.each_with_object({}) do |record, latest|
      latest[[ record.import_event_type, record.source_identifier ]] = record
    end.values
  end

  private

  def normalize_attributes
    self.import_event_type = import_event_type.to_s.strip
    self.source_identifier = source_identifier.to_s.strip
    self.payload = {} unless payload.is_a?(Hash)
    self.detail_payload = {} unless detail_payload.is_a?(Hash)
  end

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
  end

  def detail_payload_must_be_hash
    errors.add(:detail_payload, "must be a hash") unless detail_payload.is_a?(Hash)
  end
end
