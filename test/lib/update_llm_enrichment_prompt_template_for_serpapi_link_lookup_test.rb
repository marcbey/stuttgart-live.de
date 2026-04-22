require "test_helper"
require Rails.root.join(
  "db/migrate/20260416233000_update_llm_enrichment_prompt_template_for_serpapi_link_lookup"
).to_s

class UpdateLlmEnrichmentPromptTemplateForSerpapiLinkLookupTest < ActiveSupport::TestCase
  setup do
    @migration = UpdateLlmEnrichmentPromptTemplateForSerpapiLinkLookup.new
    AppSetting.where(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY).delete_all
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.where(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY).delete_all
    AppSetting.reset_cache!
  end

  test "up updates the previous default template to the new default" do
    setting = AppSetting.new(
      key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY,
      value: UpdateLlmEnrichmentPromptTemplateForSerpapiLinkLookup::PREVIOUS_TEMPLATE
    )
    setting.save!(validate: false)

    @migration.up

    assert_equal AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE, setting.reload.value
  end

  test "up keeps custom templates unchanged" do
    custom_template = "Eigener Prompt\n{{input_json}}"
    setting = AppSetting.new(
      key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY,
      value: custom_template
    )
    setting.save!(validate: false)

    @migration.up

    assert_equal custom_template, setting.reload.value
  end
end
