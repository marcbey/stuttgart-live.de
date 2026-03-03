class EventChangeLog < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true

  validates :action, presence: true

  before_validation :normalize_attributes

  private

  def normalize_attributes
    self.action = action.to_s.strip
    self.changed_fields = {} unless changed_fields.is_a?(Hash)
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
