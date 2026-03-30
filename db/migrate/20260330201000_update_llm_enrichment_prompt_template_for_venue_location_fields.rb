class UpdateLlmEnrichmentPromptTemplateForVenueLocationFields < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  def up
    setting = AppSettingMigration.find_by(key: "llm_enrichment_prompt_template")
    return unless setting
    return if venue_location_fields_present?(setting.value)

    setting.update!(value: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE)
  end

  def down
    setting = AppSettingMigration.find_by(key: "llm_enrichment_prompt_template")
    return unless setting
    return unless setting.value.to_s.strip == AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE

    setting.update!(value: remove_venue_location_field_lines(setting.value.to_s))
  end

  private

  def venue_location_fields_present?(value)
    normalized = value.to_s
    normalized.include?("`venue_external_url`") && normalized.include?("`venue_address`")
  end

  def remove_venue_location_field_lines(value)
    value
      .gsub(/\n    - `venue_external_url`/, "")
      .gsub(/\n    - `venue_address`/, "")
      .gsub(/\n      - `venue_external_url`:[^\n]*/, "")
      .gsub(/\n      - `venue_address`:[^\n]*/, "")
      .sub("\n    10. Für Venue-Metadaten gilt zusätzlich:\n", "\n")
      .sub("\n    11. Beschreibungen sollen", "\n    10. Beschreibungen sollen")
      .sub("\n    12. Nutze zusätzlich", "\n    11. Nutze zusätzlich")
      .sub("\n    13. Ziehe auch", "\n    12. Ziehe auch")
      .sub("\n    14. Wenn Artist-Name oder Event-Name mehrdeutig sind", "\n    13. Wenn Artist-Name oder Event-Name mehrdeutig sind")
      .sub("\n    15. Falls du für einen Link keinen ausreichend belastbaren Treffer findest", "\n    14. Falls du für einen Link keinen ausreichend belastbaren Treffer findest")
      .gsub("`youtube_link`, `instagram_link`, `homepage_link`, `facebook_link` und `venue_external_url`", "`youtube_link`, `instagram_link`, `homepage_link` und `facebook_link`")
  end
end
