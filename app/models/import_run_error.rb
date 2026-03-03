class ImportRunError < ApplicationRecord
  belongs_to :import_run

  validates :source_type, :message, presence: true

  before_validation :normalize_attributes

  private

  def normalize_attributes
    self.source_type = source_type.to_s.strip
    self.external_event_id = external_event_id.to_s.strip.presence
    self.error_class = error_class.to_s.strip.presence
    self.payload = {} unless payload.is_a?(Hash)
  end
end
