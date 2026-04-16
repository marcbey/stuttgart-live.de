class SeedLlmEnrichmentTemperatureSetting < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  DEFAULT_LLM_ENRICHMENT_TEMPERATURE = 1

  def up
    AppSettingMigration.find_or_create_by!(key: "llm_enrichment_temperature") do |setting|
      setting.value = DEFAULT_LLM_ENRICHMENT_TEMPERATURE
    end
  end

  def down
    AppSettingMigration.where(
      key: "llm_enrichment_temperature",
      value: DEFAULT_LLM_ENRICHMENT_TEMPERATURE
    ).delete_all
  end
end
