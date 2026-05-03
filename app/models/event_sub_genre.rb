class EventSubGenre < ApplicationRecord
  belongs_to :event
  belongs_to :sub_genre

  validates :sub_genre_id, uniqueness: { scope: :event_id }
end
