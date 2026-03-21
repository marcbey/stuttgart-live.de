class EventLlmEnrichment < ApplicationRecord
  belongs_to :event
  belongs_to :source_run, class_name: "ImportRun"

  validates :event_id, uniqueness: true
  validates :model, :prompt_version, presence: true
  validate :genre_must_be_string_array
  validate :raw_response_must_be_hash

  before_validation :normalize_attributes

  def genre_list
    return @genre_list if defined?(@genre_list)

    Array(genre).join("\n")
  end

  def genre_list=(value)
    @genre_list = value.to_s
    self.genre = @genre_list.split(/[\n,;]+/)
  end

  private

  def normalize_attributes
    self.genre = Array(genre).filter_map do |entry|
      value = entry.to_s.strip
      value.presence
    end.uniq
    self.venue = venue.to_s.strip.presence
    self.artist_description = artist_description.to_s.strip.presence
    self.event_description = event_description.to_s.strip.presence
    self.venue_description = venue_description.to_s.strip.presence
    self.youtube_link = youtube_link.to_s.strip.presence
    self.instagram_link = instagram_link.to_s.strip.presence
    self.homepage_link = homepage_link.to_s.strip.presence
    self.facebook_link = facebook_link.to_s.strip.presence
    self.model = model.to_s.strip
    self.prompt_version = prompt_version.to_s.strip
    self.raw_response = {} unless raw_response.is_a?(Hash)
  end

  def genre_must_be_string_array
    errors.add(:genre, "must be an array") unless genre.is_a?(Array)
  end

  def raw_response_must_be_hash
    errors.add(:raw_response, "must be a hash") unless raw_response.is_a?(Hash)
  end
end
