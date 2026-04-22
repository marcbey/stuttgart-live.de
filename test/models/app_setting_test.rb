require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  teardown do
    AppSetting.reset_cache!
  end

  test "normalizes sks promoter ids from text" do
    setting = AppSetting.new(key: AppSetting::SKS_PROMOTER_IDS_KEY)
    setting.sks_promoter_ids_text = "10135\n10136, 382\n10135"

    assert_equal %w[10135 10136 382], setting.sks_promoter_ids
  end

  test "returns configured sks promoter ids" do
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: %w[500 600])

    assert_equal %w[500 600], AppSetting.sks_promoter_ids
  end

  test "returns seeded sks promoter ids from the database" do
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: %w[10135 10136 382])
    AppSetting.reset_cache!

    assert_equal %w[10135 10136 382], AppSetting.sks_promoter_ids
  end

  test "requires at least one configured sks promoter id" do
    setting = AppSetting.new(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [])

    assert_not setting.valid?
    assert_includes setting.errors[:value], "muss mindestens eine Promoter-ID enthalten"
  end

  test "normalizes sks organizer notes text" do
    setting = AppSetting.new(key: AppSetting::SKS_ORGANIZER_NOTES_KEY)
    setting.sks_organizer_notes_text = " Hinweis eins \nHinweis zwei \n"

    assert_equal "Hinweis eins \nHinweis zwei", setting.sks_organizer_notes
  end

  test "returns configured sks organizer notes" do
    AppSetting.create!(key: AppSetting::SKS_ORGANIZER_NOTES_KEY, value: "Line one\nLine two")

    assert_equal "Line one\nLine two", AppSetting.sks_organizer_notes
  end

  test "normalizes homepage genre lane slugs from text" do
    setting = AppSetting.new(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY)
    setting.homepage_genre_lane_slugs_text = "Rock & Alternative\npop-mainstream, Rock & Alternative\n"

    assert_equal [ "rock-alternative", "pop-mainstream" ], setting.homepage_genre_lane_slugs
    assert_equal "rock-alternative\npop-mainstream", setting.homepage_genre_lane_slugs_text
  end

  test "normalizes homepage genre lane slugs from checkbox array" do
    setting = AppSetting.new(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY)
    setting.homepage_genre_lane_slugs = [ "", "Rock & Alternative", "pop-mainstream", "Rock & Alternative" ]

    assert_equal [ "rock-alternative", "pop-mainstream" ], setting.homepage_genre_lane_slugs
  end

  test "returns configured homepage genre lane slugs" do
    AppSetting.create!(key: AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY, value: [ "rock-alternative", "pop-mainstream" ])

    assert_equal [ "rock-alternative", "pop-mainstream" ], AppSetting.homepage_genre_lane_slugs
  end

  test "returns empty homepage genre lane slugs when not configured" do
    assert_equal [], AppSetting.homepage_genre_lane_slugs
  end

  test "normalizes public genre grouping snapshot id" do
    setting = AppSetting.new(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY)
    setting.public_genre_grouping_snapshot_id = "42"

    assert_equal 42, setting.public_genre_grouping_snapshot_id
  end

  test "returns configured public genre grouping snapshot id" do
    AppSetting.create!(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY, value: 7)

    assert_equal 7, AppSetting.public_genre_grouping_snapshot_id
  end

  test "rejects invalid public genre grouping snapshot id" do
    setting = AppSetting.new(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY, value: "abc")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "muss eine positive Ganzzahl sein"
  end

  test "returns default llm enrichment prompt template when no setting exists" do
    assert_includes AppSetting.llm_enrichment_prompt_template, "{{input_json}}"
    assert_includes AppSetting.llm_enrichment_prompt_template, "`venue_external_url`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "`event_info`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "`youtube_link`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "`instagram_link`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "`homepage_link`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "`facebook_link`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "`search_results.fields.<feld>.candidates`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "nicht den bloßen Eventtyp oder einen Containerbegriff"
    assert_includes AppSetting.llm_enrichment_prompt_template, "`show`, `concert`, `event`, `live`, `veranstaltung`, `konzert`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "gib lieber ein leeres Genre-Array zurück"
    assert_includes AppSetting.llm_enrichment_prompt_template, "ohne Wiederholungen"
    assert_includes AppSetting.llm_enrichment_prompt_template, "Output:"
    assert_includes AppSetting.llm_enrichment_prompt_template, "\"genre\": [ \"Indie Pop\" ]"
    assert_includes AppSetting.llm_enrichment_prompt_template, "\"youtube_link\": \"https://www.youtube.com/@artist\""
    assert_not_includes AppSetting.llm_enrichment_prompt_template, "`artist_description`"
    assert_not_includes AppSetting.llm_enrichment_prompt_template, "`link_query`"
    assert_not_includes AppSetting.llm_enrichment_prompt_template, "\"link_query\":"
  end

  test "returns default llm enrichment model when no setting exists" do
    assert_equal "gpt-5.1", AppSetting.llm_enrichment_model
  end

  test "returns configured llm enrichment model" do
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-5-mini")

    assert_equal "gpt-5-mini", AppSetting.llm_enrichment_model
  end

  test "returns default llm enrichment temperature when no setting exists" do
    assert_equal 1.0, AppSetting.llm_enrichment_temperature
  end

  test "returns configured llm enrichment temperature" do
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_TEMPERATURE_KEY, value: 0.4)

    assert_equal 0.4, AppSetting.llm_enrichment_temperature
  end

  test "returns default llm enrichment search providers when not configured" do
    assert_equal "serpapi", AppSetting.llm_enrichment_web_search_provider
  end

  test "returns configured llm enrichment web search provider" do
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_WEB_SEARCH_PROVIDER_KEY, value: "openwebninja")

    assert_equal "openwebninja", AppSetting.llm_enrichment_web_search_provider
  end

  test "normalizes llm enrichment temperature from text" do
    setting = AppSetting.new(key: AppSetting::LLM_ENRICHMENT_TEMPERATURE_KEY)
    setting.llm_enrichment_temperature = " 0.7 "

    assert_equal 0.7, setting.llm_enrichment_temperature
  end

  test "supports gpt-5.4 for llm settings" do
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-5.4")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_MODEL_KEY, value: "gpt-5.4")

    assert_equal "gpt-5.4", AppSetting.llm_enrichment_model
    assert_equal "gpt-5.4", AppSetting.llm_genre_grouping_model
  end

  test "requires llm enrichment model to be supported" do
    setting = AppSetting.new(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-4.1")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "ist kein unterstütztes LLM-Modell"
  end

  test "returns configured llm enrichment prompt template" do
    custom_prompt = <<~TEXT.strip
      Nutze search_results und candidates für homepage_link, instagram_link, facebook_link, youtube_link und venue_external_url.
      {{input_json}}
    TEXT
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: custom_prompt)

    assert_equal custom_prompt, AppSetting.llm_enrichment_prompt_template
  end

  test "falls back to default llm enrichment prompt template when configured prompt is incompatible" do
    AppSetting.new(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: "Prompt\n{{input_json}}").save!(validate: false)

    assert_equal AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE, AppSetting.llm_enrichment_prompt_template
  end

  test "requires llm enrichment prompt template to contain input placeholder" do
    setting = AppSetting.new(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: "Prompt ohne Platzhalter")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "{{input_json}} muss im Prompt enthalten sein"
  end

  test "requires llm enrichment prompt template to include search context fields" do
    setting = AppSetting.new(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: "Prompt\n{{input_json}}")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "muss die Felder homepage_link, instagram_link, facebook_link, youtube_link, venue_external_url sowie search_results/candidates berücksichtigen"
  end

  test "requires llm enrichment temperature to be between 0 and 2" do
    setting = AppSetting.new(key: AppSetting::LLM_ENRICHMENT_TEMPERATURE_KEY, value: "2.5")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "muss eine Zahl zwischen 0 und 2 sein"
  end

  test "requires llm enrichment web search provider to be supported" do
    setting = AppSetting.new(key: AppSetting::LLM_ENRICHMENT_WEB_SEARCH_PROVIDER_KEY, value: "bing")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "ist kein unterstützter Web-Search-Provider"
  end

  test "returns default llm genre grouping prompt template when no setting exists" do
    assert_includes AppSetting.llm_genre_grouping_prompt_template, "{{input_json}}"
    assert_includes AppSetting.llm_genre_grouping_prompt_template, "{{group_count}}"
  end

  test "returns default llm genre grouping model when no setting exists" do
    assert_equal "gpt-5.1", AppSetting.llm_genre_grouping_model
  end

  test "returns default llm genre grouping group count when no setting exists" do
    assert_equal 30, AppSetting.llm_genre_grouping_group_count
  end

  test "returns configured llm genre grouping settings" do
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_MODEL_KEY, value: "gpt-5.4")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY, value: "Gruppiere\n{{group_count}}\n{{input_json}}")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_KEY, value: 42)

    assert_equal "gpt-5.4", AppSetting.llm_genre_grouping_model
    assert_equal "Gruppiere\n{{group_count}}\n{{input_json}}", AppSetting.llm_genre_grouping_prompt_template
    assert_equal 42, AppSetting.llm_genre_grouping_group_count
  end

  test "requires llm genre grouping prompt template to contain both placeholders" do
    setting = AppSetting.new(key: AppSetting::LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY, value: "Prompt\n{{input_json}}")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "{{group_count}} muss im Prompt enthalten sein"
  end

  test "requires llm genre grouping model to be supported" do
    setting = AppSetting.new(key: AppSetting::LLM_GENRE_GROUPING_MODEL_KEY, value: "gpt-4.1")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "ist kein unterstütztes LLM-Modell"
  end

  test "requires llm genre grouping group count to be positive" do
    setting = AppSetting.new(key: AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_KEY, value: 0)

    assert_not setting.valid?
    assert_includes setting.errors[:value], "muss eine positive Ganzzahl sein"
  end

  test "returns true for merge similarity matching when not configured" do
    assert_equal true, AppSetting.merge_artist_similarity_matching_enabled?
  end

  test "returns configured merge similarity matching flag" do
    AppSetting.create!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY, value: true)

    assert_equal true, AppSetting.merge_artist_similarity_matching_enabled?
  end

  test "allows disabling merge similarity matching explicitly" do
    AppSetting.create!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY, value: false)

    assert_equal false, AppSetting.merge_artist_similarity_matching_enabled?
  end

  test "normalizes merge similarity matching value from boolean-like input" do
    setting = AppSetting.new(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY)

    setting.merge_artist_similarity_matching_enabled = "0"
    assert_equal false, setting.merge_artist_similarity_matching_enabled

    setting.merge_artist_similarity_matching_enabled = "1"
    assert_equal true, setting.merge_artist_similarity_matching_enabled
  end
end
