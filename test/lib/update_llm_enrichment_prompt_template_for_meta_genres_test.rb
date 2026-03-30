require "test_helper"
require Rails.root.join(
  "db/migrate/20260330220000_update_llm_enrichment_prompt_template_for_meta_genres"
).to_s

class UpdateLlmEnrichmentPromptTemplateForMetaGenresTest < ActiveSupport::TestCase
  setup do
    @migration = UpdateLlmEnrichmentPromptTemplateForMetaGenres.new
    AppSetting.where(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY).delete_all
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.where(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY).delete_all
    AppSetting.reset_cache!
  end

  test "up updates the previous default template to the new default" do
    setting = AppSetting.create!(
      key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY,
      value: UpdateLlmEnrichmentPromptTemplateForMetaGenres::PREVIOUS_TEMPLATE
    )

    @migration.up

    assert_equal AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE, setting.reload.value
  end

  test "up keeps custom templates unchanged" do
    custom_template = "Eigener Prompt\n{{input_json}}"
    setting = AppSetting.create!(
      key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY,
      value: custom_template
    )

    @migration.up

    assert_equal custom_template, setting.reload.value
  end
end
