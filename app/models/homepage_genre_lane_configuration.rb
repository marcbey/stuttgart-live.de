class HomepageGenreLaneConfiguration < ApplicationRecord
  belongs_to :snapshot,
    class_name: "LlmGenreGroupingSnapshot",
    foreign_key: :snapshot_id,
    inverse_of: :homepage_genre_lane_configuration

  validates :snapshot_id, uniqueness: true
  validate :lane_slugs_must_be_array

  before_validation :normalize_lane_slugs

  def lane_slugs
    AppSetting.normalize_slug_list(self[:lane_slugs])
  end

  def lane_slugs=(raw_value)
    self[:lane_slugs] = AppSetting.normalize_slug_list(raw_value)
  end

  private

  def normalize_lane_slugs
    self[:lane_slugs] = AppSetting.normalize_slug_list(self[:lane_slugs])
  end

  def lane_slugs_must_be_array
    errors.add(:lane_slugs, "must be an array") unless self[:lane_slugs].is_a?(Array)
  end
end
