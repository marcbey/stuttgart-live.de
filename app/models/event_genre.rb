class EventGenre < ApplicationRecord
  belongs_to :event
  belongs_to :genre

  validates :genre_id, uniqueness: { scope: :event_id }
end
