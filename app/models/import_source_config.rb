class ImportSourceConfig < ApplicationRecord
  RESERVIX_CHECKPOINT_KEY = "reservix_checkpoint".freeze

  belongs_to :import_source

  validates :import_source_id, uniqueness: true
  validate :settings_must_be_hash

  before_validation :apply_defaults

  def location_whitelist
    normalize_location_list(settings.fetch("location_whitelist", []))
  end

  def location_whitelist=(value)
    self.settings = settings.merge("location_whitelist" => normalize_location_list(value))
  end

  def reservix_checkpoint
    raw = settings.fetch(RESERVIX_CHECKPOINT_KEY, {})
    return {} unless raw.is_a?(Hash)

    normalized = raw.deep_stringify_keys
    checkpoint = {}

    lastupdate = normalized["lastupdate"].to_s.strip
    checkpoint["lastupdate"] = lastupdate if lastupdate.present?

    last_processed_event_id = normalized["last_processed_event_id"].to_s.strip
    checkpoint["last_processed_event_id"] = last_processed_event_id if last_processed_event_id.present?

    checkpoint
  end

  def reservix_checkpoint=(value)
    self.settings = settings.merge(RESERVIX_CHECKPOINT_KEY => normalize_reservix_checkpoint(value))
  end

  private

  def apply_defaults
    self.settings = {} unless settings.is_a?(Hash)
  end

  def settings_must_be_hash
    errors.add(:settings, "must be a hash") unless settings.is_a?(Hash)
  end

  def normalize_location_list(value)
    raw_values =
      case value
      when String
        value.split(/[\n,]/)
      when Array
        value
      else
        Array(value)
      end

    raw_values
      .map { |entry| entry.to_s.strip }
      .reject(&:blank?)
      .uniq
  end

  def normalize_reservix_checkpoint(value)
    raw = value.is_a?(Hash) ? value.deep_stringify_keys : {}
    checkpoint = {}

    lastupdate = raw["lastupdate"].to_s.strip
    checkpoint["lastupdate"] = lastupdate if lastupdate.present?

    last_processed_event_id = raw["last_processed_event_id"].to_s.strip
    checkpoint["last_processed_event_id"] = last_processed_event_id if last_processed_event_id.present?

    checkpoint
  end
end
