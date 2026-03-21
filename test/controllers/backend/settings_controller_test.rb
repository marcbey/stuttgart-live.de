require "test_helper"

class Backend::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)
    @editor = users(:one)
    reset_settings!
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "admin can edit settings with tab shell and default section" do
    sign_in_as(@admin)
    seed_all_settings!
    create_homepage_genre_snapshot

    get edit_backend_settings_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Einstellungen"
    assert_select "[data-controller='settings-tabs']", count: 1
    assert_select "[role='tab']", count: 6
    assert_select "#settings-tab-sks-promoter-ids[aria-selected='true']", count: 1
    assert_select "form[action='#{backend_settings_path(section: :sks_promoter_ids)}'] textarea[name='app_setting[sks_promoter_ids_text]']", count: 1
    assert_select "textarea[name='app_setting[llm_enrichment_prompt_template_text]']", count: 0
  end

  test "admin can open specific section via query param" do
    sign_in_as(@admin)
    seed_all_settings!

    get edit_backend_settings_url(section: :llm_genre_grouping)

    assert_response :success
    assert_select "#settings-tab-llm-genre-grouping[aria-selected='true']", count: 1
    assert_select "form[action='#{backend_settings_path(section: :llm_genre_grouping)}'] select[name='app_setting[llm_genre_grouping_model]']", count: 1
    assert_select "textarea[name='app_setting[sks_promoter_ids_text]']", count: 0
  end

  test "invalid section falls back to default tab" do
    sign_in_as(@admin)

    get edit_backend_settings_url(section: :unknown)

    assert_response :success
    assert_select "#settings-tab-sks-promoter-ids[aria-selected='true']", count: 1
  end

  test "admin can load a section partial" do
    sign_in_as(@admin)
    seed_all_settings!

    get section_backend_settings_url(section: :llm_enrichment)

    assert_response :success
    assert_select "section.settings-group", count: 1
    assert_select "form[action='#{backend_settings_path(section: :llm_enrichment)}'] select[name='app_setting[llm_enrichment_model]']", count: 1
    assert_select ".settings-tabs-nav", count: 0
  end

  test "editor cannot access settings" do
    sign_in_as(@editor)

    get edit_backend_settings_url

    assert_redirected_to backend_root_url
  end

  test "admin can update sks promoter ids without touching other settings" do
    sign_in_as(@admin)
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-5.1")

    patch backend_settings_url(section: :sks_promoter_ids), params: {
      app_setting: {
        sks_promoter_ids_text: "900\n901, 902"
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :sks_promoter_ids)
    assert_equal %w[900 901 902], AppSetting.sks_promoter_ids
    assert_equal "gpt-5.1", AppSetting.llm_enrichment_model
  end

  test "admin can update llm enrichment section" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_enrichment), params: {
      app_setting: {
        llm_enrichment_model: "gpt-5-mini",
        llm_enrichment_prompt_template_text: "Bitte recherchiere\n{{input_json}}"
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :llm_enrichment)
    assert_equal "gpt-5-mini", AppSetting.llm_enrichment_model
    assert_equal "Bitte recherchiere\n{{input_json}}", AppSetting.llm_enrichment_prompt_template
  end

  test "admin can update homepage genre lanes section" do
    sign_in_as(@admin)
    snapshot = create_homepage_genre_snapshot

    patch backend_settings_url(section: :homepage_genre_lanes), params: {
      app_setting: {
        public_genre_grouping_snapshot_id: snapshot.id,
        homepage_genre_lane_slugs: [ "rock-alternative", "pop-mainstream" ]
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot.id)
    assert_equal snapshot.id, AppSetting.public_genre_grouping_snapshot_id
    assert_equal [ "rock-alternative", "pop-mainstream" ], snapshot.reload.homepage_genre_lane_configuration.lane_slugs
  end

  test "homepage genre lanes section shows the stored configuration of the selected snapshot" do
    sign_in_as(@admin)
    snapshot_one = create_homepage_genre_snapshot(selected: true, lane_slugs: [ "rock-alternative" ])
    snapshot_two = create_homepage_genre_snapshot(lane_slugs: [ "pop-mainstream" ])

    get edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot_two.id)

    assert_response :success
    assert_select "input[name='app_setting[homepage_genre_lane_slugs][]'][value='pop-mainstream'][checked='checked']", count: 1
    assert_select "input[name='app_setting[homepage_genre_lane_slugs][]'][value='rock-alternative'][checked='checked']", count: 0

    get edit_backend_settings_url(section: :homepage_genre_lanes, selected_snapshot_id: snapshot_one.id)

    assert_response :success
    assert_select "input[name='app_setting[homepage_genre_lane_slugs][]'][value='rock-alternative'][checked='checked']", count: 1
    assert_select "input[name='app_setting[homepage_genre_lane_slugs][]'][value='pop-mainstream'][checked='checked']", count: 0
  end

  test "admin can enable similarity matching in settings" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :merge_artist_similarity_matching), params: {
      app_setting: {
        merge_artist_similarity_matching_enabled: "1"
      }
    }

    assert_redirected_to edit_backend_settings_url(section: :merge_artist_similarity_matching)
    assert_equal true, AppSetting.merge_artist_similarity_matching_enabled?
    assert_equal true, AppSetting.find_by!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).value
  end

  test "admin cannot save empty sks promoter ids" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :sks_promoter_ids), params: {
      app_setting: {
        sks_promoter_ids_text: " \n "
      }
    }

    assert_response :unprocessable_entity
    assert_select "#settings-tab-sks-promoter-ids[aria-selected='true']", count: 1
    assert_includes response.body, "muss mindestens eine Promoter-ID enthalten"
  end

  test "admin cannot save llm enrichment prompt without input placeholder" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_enrichment), params: {
      app_setting: {
        llm_enrichment_model: "gpt-5.1",
        llm_enrichment_prompt_template_text: "Prompt ohne Platzhalter"
      }
    }

    assert_response :unprocessable_entity
    assert_select "#settings-tab-llm-enrichment[aria-selected='true']", count: 1
    assert_includes response.body, "{{input_json}} muss im Prompt enthalten sein"
  end

  test "admin cannot save unsupported llm enrichment model" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_enrichment), params: {
      app_setting: {
        llm_enrichment_model: "gpt-4.1",
        llm_enrichment_prompt_template_text: "Prompt\n{{input_json}}"
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "ist kein unterstütztes LLM-Modell"
  end

  test "admin cannot save invalid llm genre grouping settings" do
    sign_in_as(@admin)

    patch backend_settings_url(section: :llm_genre_grouping), params: {
      app_setting: {
        llm_genre_grouping_model: "gpt-5-mini",
        llm_genre_grouping_prompt_template_text: "Gruppiere\n{{input_json}}",
        llm_genre_grouping_group_count: "0"
      }
    }

    assert_response :unprocessable_entity
    assert_select "#settings-tab-llm-genre-grouping[aria-selected='true']", count: 1
    assert_includes response.body, "{{group_count}} muss im Prompt enthalten sein"
    assert_includes response.body, "muss eine positive Ganzzahl sein"
  end

  private

  def reset_settings!
    [
      AppSetting::SKS_PROMOTER_IDS_KEY,
      AppSetting::SKS_ORGANIZER_NOTES_KEY,
      AppSetting::HOMEPAGE_GENRE_LANE_SLUGS_KEY,
      AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY,
      AppSetting::LLM_ENRICHMENT_MODEL_KEY,
      AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY,
      AppSetting::LLM_GENRE_GROUPING_MODEL_KEY,
      AppSetting::LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY,
      AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_KEY,
      AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY
    ].each do |key|
      AppSetting.where(key: key).delete_all
    end

    AppSetting.reset_cache!
  end

  def seed_all_settings!
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: %w[10135 10136 382])
    AppSetting.create!(key: AppSetting::SKS_ORGANIZER_NOTES_KEY, value: "Bestehender Hinweistext")
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-5-mini")
    AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE_KEY, value: "Prompt\n{{input_json}}")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_MODEL_KEY, value: "gpt-5-mini")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_PROMPT_TEMPLATE_KEY, value: "Gruppiere\n{{group_count}}\n{{input_json}}")
    AppSetting.create!(key: AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_KEY, value: 30)
    AppSetting.create!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY, value: true)
    AppSetting.reset_cache!
  end

  def create_homepage_genre_snapshot(selected: false, lane_slugs: [])
    run = import_sources(:two).import_runs.create!(
      source_type: "llm_genre_grouping",
      status: "succeeded",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )

    snapshot = run.create_llm_genre_grouping_snapshot!(
      active: false,
      requested_group_count: 30,
      effective_group_count: 2,
      source_genres_count: 2,
      model: "gpt-5-mini",
      prompt_template_digest: "digest",
      request_payload: {},
      raw_response: {}
    )

    snapshot.groups.create!(position: 1, name: "Rock & Alternative", member_genres: [ "Rock" ])
    snapshot.groups.create!(position: 2, name: "Pop & Mainstream", member_genres: [ "Pop" ])
    snapshot.create_homepage_genre_lane_configuration!(lane_slugs:)
    AppSetting.create!(key: AppSetting::PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY, value: snapshot.id) if selected

    snapshot
  end
end
