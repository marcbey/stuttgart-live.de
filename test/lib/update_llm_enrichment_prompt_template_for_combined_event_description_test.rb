require "test_helper"
require Rails.root.join(
  "db/migrate/20260330213100_update_llm_enrichment_prompt_template_for_combined_event_description"
).to_s

class UpdateLlmEnrichmentPromptTemplateForCombinedEventDescriptionTest < ActiveSupport::TestCase
  setup do
    @migration = UpdateLlmEnrichmentPromptTemplateForCombinedEventDescription.new
    AppSetting.where(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY).delete_all
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.where(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY).delete_all
    AppSetting.reset_cache!
  end

  test "up replaces templates that still reference artist_description" do
    setting = AppSetting.new(
      key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY,
      value: "Prompt\n- `artist_description`\n{{input_json}}"
    )
    setting.save!(validate: false)

    @migration.up

    assert_equal AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE, setting.reload.value
  end

  test "up keeps compatible templates unchanged" do
    custom_template = "Prompt\n- `event_description`\n{{input_json}}"
    setting = AppSetting.new(
      key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY,
      value: custom_template
    )
    setting.save!(validate: false)

    @migration.up

    assert_equal custom_template, setting.reload.value
  end
end
