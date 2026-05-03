class EventLlmEnrichment < ApplicationRecord
  belongs_to :event
  belongs_to :source_run, class_name: "ImportRun"

  validates :event_id, uniqueness: true
  validates :model, :prompt_version, presence: true
  validate :raw_response_must_be_hash

  before_validation :normalize_attributes

  private

  def normalize_attributes
    self.venue = venue.to_s.strip.presence
    self.event_description = event_description.to_s.strip.presence
    self.venue_description = venue_description.to_s.strip.presence
    self.venue_external_url = venue_external_url.to_s.strip.presence
    self.venue_address = venue_address.to_s.strip.presence
    self.youtube_link = youtube_link.to_s.strip.presence
    self.instagram_link = instagram_link.to_s.strip.presence
    self.homepage_link = homepage_link.to_s.strip.presence
    self.facebook_link = facebook_link.to_s.strip.presence
    self.model = model.to_s.strip
    self.prompt_version = prompt_version.to_s.strip
    self.raw_response = {} unless raw_response.is_a?(Hash)
  end

  def raw_response_must_be_hash
    errors.add(:raw_response, "must be a hash") unless raw_response.is_a?(Hash)
  end
end
