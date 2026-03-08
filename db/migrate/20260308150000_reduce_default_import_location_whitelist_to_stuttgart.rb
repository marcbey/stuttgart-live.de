class ReduceDefaultImportLocationWhitelistToStuttgart < ActiveRecord::Migration[8.1]
  OLD_DEFAULTS = [
    "Stuttgart",
    "Stuttgart - Bad Cannstatt",
    "Stuttgart Bad-Cannstatt",
    "Esslingen am Neckar"
  ].freeze

  NEW_DEFAULTS = [ "Stuttgart" ].freeze

  class ImportSourceConfigMigration < ApplicationRecord
    self.table_name = "import_source_configs"
  end

  def up
    update_matching_defaults(from: OLD_DEFAULTS, to: NEW_DEFAULTS)
  end

  def down
    update_matching_defaults(from: NEW_DEFAULTS, to: OLD_DEFAULTS)
  end

  private
    def update_matching_defaults(from:, to:)
      ImportSourceConfigMigration.find_each do |config|
        settings = config.settings.is_a?(Hash) ? config.settings.deep_stringify_keys : {}
        whitelist = normalize_location_list(settings["location_whitelist"])
        next unless whitelist == from

        config.update!(settings: settings.merge("location_whitelist" => to))
      end
    end

    def normalize_location_list(value)
      Array(value).map { |entry| entry.to_s.strip }.reject(&:blank?).uniq
    end
end
