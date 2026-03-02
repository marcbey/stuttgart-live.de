class ImportSourceConfig < ApplicationRecord
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
end
