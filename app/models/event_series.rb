class EventSeries < ApplicationRecord
  ORIGINS = %w[imported manual].freeze

  has_many :events, dependent: :nullify

  validates :origin, presence: true, inclusion: { in: ORIGINS }
  validates :source_type, :source_key, presence: true, if: :imported?
  validates :source_key, uniqueness: { scope: :source_type }, allow_nil: true

  scope :imported, -> { where(origin: "imported") }
  scope :manual, -> { where(origin: "manual") }

  def imported?
    origin == "imported"
  end

  def manual?
    origin == "manual"
  end

  def display_name
    name.to_s.strip.presence ||
      events.chronological.limit(1).pick(:title).to_s.strip.presence ||
      "Event-Reihe"
  end

  def destroy_if_orphaned!
    destroy! unless events.exists?
  end
end
