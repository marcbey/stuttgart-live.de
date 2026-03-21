class EventPresenter < ApplicationRecord
  belongs_to :event
  belongs_to :presenter

  validates :position, numericality: { greater_than: 0, only_integer: true }
  validates :presenter_id, uniqueness: { scope: :event_id }
  validates :position, uniqueness: { scope: :event_id }
end
