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
    assert_includes AppSetting.llm_enrichment_prompt_template, "kein `404`"
    assert_includes AppSetting.llm_enrichment_prompt_template, "Diese Seite ist leider nicht verfügbar"
    assert_includes AppSetting.llm_enrichment_prompt_template, "Dieser Inhalt ist momentan nicht verfügbar"
  end

  test "returns default llm enrichment model when no setting exists" do
    assert_equal "gpt-5.1", AppSetting.llm_enrichment_model
  end

  test "returns configured llm enrichment model" do
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-5-mini")

    assert_equal "gpt-5-mini", AppSetting.llm_enrichment_model
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
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: "Prompt\n{{input_json}}")

    assert_equal "Prompt\n{{input_json}}", AppSetting.llm_enrichment_prompt_template
  end

  test "requires llm enrichment prompt template to contain input placeholder" do
    setting = AppSetting.new(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: "Prompt ohne Platzhalter")

    assert_not setting.valid?
    assert_includes setting.errors[:value], "{{input_json}} muss im Prompt enthalten sein"
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
