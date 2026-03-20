class LlmGenreGroupingGroup < ApplicationRecord
  belongs_to :snapshot,
    class_name: "LlmGenreGroupingSnapshot",
    foreign_key: :snapshot_id,
    inverse_of: :groups

  validates :position, numericality: { greater_than: 0, only_integer: true }, uniqueness: { scope: :snapshot_id }
  validates :name, :slug, presence: true
  validates :slug, uniqueness: { scope: :snapshot_id }
  validate :member_genres_must_be_string_array
  validate :member_genres_must_not_be_empty

  before_validation :normalize_attributes

  def genre_count
    member_genres.size
  end

  private

  def normalize_attributes
    self.name = name.to_s.strip
    self.slug = name.to_s.parameterize.presence || slug.to_s.parameterize.presence || position_slug
    self.member_genres = Array(member_genres).filter_map do |entry|
      value = entry.to_s.strip
      value.presence
    end.uniq.sort
  end

  def member_genres_must_be_string_array
    errors.add(:member_genres, "must be an array") unless member_genres.is_a?(Array)
  end

  def member_genres_must_not_be_empty
    return unless member_genres.is_a?(Array)
    return if member_genres.any?

    errors.add(:member_genres, "must not be empty")
  end

  def position_slug
    return nil if position.blank?

    "group-#{position}"
  end
end
