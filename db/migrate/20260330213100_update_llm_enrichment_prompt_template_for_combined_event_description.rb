class UpdateLlmEnrichmentPromptTemplateForCombinedEventDescription < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  def up
    setting = AppSettingMigration.find_by(key: "llm_enrichment_prompt_template")
    return unless setting
    return unless setting.value.to_s.include?("`artist_description`")

    setting.update!(value: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE)
  end

  def down
    setting = AppSettingMigration.find_by(key: "llm_enrichment_prompt_template")
    return unless setting
    return unless setting.value.to_s.strip == AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE

    setting.update!(value: revert_combined_event_description(setting.value.to_s))
  end

  private

  def revert_combined_event_description(value)
    value
      .sub("\n    - `event_description`\n", "\n    - `artist_description`\n    - `event_description`\n")
      .sub(
        "- `event_description`: beschreibt Artist, Projekt oder Produktion sowie das konkrete Event bzw. Tour-/Show-Format in einem zusammenhängenden Text ohne Wiederholungen",
        "- `artist_description`: beschreibt Artist, Projekt oder Produktion\n      - `event_description`: beschreibt das konkrete Event bzw. Tour-/Show-Format"
      )
      .sub(
        "- nenne bei `event_description` nach Möglichkeit Artist-/Projektprofil, Inhalt, Format, Tour-Kontext, typische Erwartung des Publikums und Besonderheiten",
        "- nenne bei `event_description` nach Möglichkeit Inhalt, Format, Tour-Kontext, typische Erwartung des Publikums und Besonderheiten"
      )
      .sub("\n      - fasse überlappende Informationen zu Artist und Event zusammen, statt dieselben Fakten doppelt zu nennen", "")
  end
end
