class SeedDailyImportSchedulerSettings < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  SETTINGS = %w[
    daily_raw_import_enabled
    daily_merge_import_enabled
    daily_llm_enrichment_enabled
  ].freeze

  def up
    SETTINGS.each do |key|
      AppSettingMigration.find_or_create_by!(key:) do |setting|
        setting.value = true
      end
    end
  end

  def down
    SETTINGS.each do |key|
      AppSettingMigration.where(key:, value: true).delete_all
    end
  end
end
