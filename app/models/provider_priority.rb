class ProviderPriority < ApplicationRecord
  validates :source_type, presence: true, uniqueness: true, inclusion: { in: ImportSource::SOURCE_TYPES }
  validates :priority_rank, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :active, inclusion: { in: [ true, false ] }

  before_validation :normalize_attributes

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(priority_rank: :asc) }

  private

  def normalize_attributes
    self.source_type = source_type.to_s.strip
    self.active = true if active.nil?
  end
end
