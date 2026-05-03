class SubGenre < ApplicationRecord
  has_many :event_sub_genres, dependent: :destroy
  has_many :events, through: :event_sub_genres

  validates :name, :slug, presence: true
  validates :name, :slug, uniqueness: true

  before_validation :normalize_attributes

  private

  def normalize_attributes
    self.name = name.to_s.strip
    self.slug = name.parameterize if slug.blank?
  end
end
