require "test_helper"

class Backend::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)
    @editor = users(:one)
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.where(key: AppSetting::SKS_ORGANIZER_NOTES_KEY).delete_all
    AppSetting.where(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).delete_all
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "admin can edit settings" do
    sign_in_as(@admin)
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: %w[10135 10136 382])
    AppSetting.create!(key: AppSetting::SKS_ORGANIZER_NOTES_KEY, value: "Bestehender Hinweistext")
    AppSetting.create!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY, value: true)

    get edit_backend_settings_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Einstellungen"
    assert_includes response.body, "SKS Promoter IDs"
    assert_includes response.body, "SKS Standard-Veranstalterhinweise"
    assert_includes response.body, "Ähnlichkeits-Matching für Artist-Dubletten"
  end

  test "editor cannot access settings" do
    sign_in_as(@editor)

    get edit_backend_settings_url

    assert_redirected_to backend_root_url
  end

  test "admin can update sks promoter ids" do
    sign_in_as(@admin)

    patch backend_settings_url, params: {
      app_setting: {
        sks_promoter_ids_text: "900\n901, 902",
        sks_organizer_notes_text: "Neuer Hinweistext\nZweite Zeile",
        merge_artist_similarity_matching_enabled: "0"
      }
    }

    assert_redirected_to edit_backend_settings_url
    assert_equal %w[900 901 902], AppSetting.sks_promoter_ids
    assert_equal %w[900 901 902], AppSetting.find_by!(key: AppSetting::SKS_PROMOTER_IDS_KEY).value
    assert_equal "Neuer Hinweistext\nZweite Zeile", AppSetting.sks_organizer_notes
    assert_equal false, AppSetting.merge_artist_similarity_matching_enabled?
  end

  test "admin can enable similarity matching in settings" do
    sign_in_as(@admin)

    patch backend_settings_url, params: {
      app_setting: {
        sks_promoter_ids_text: "900",
        sks_organizer_notes_text: "Hinweistext",
        merge_artist_similarity_matching_enabled: "1"
      }
    }

    assert_redirected_to edit_backend_settings_url
    assert_equal true, AppSetting.merge_artist_similarity_matching_enabled?
    assert_equal true, AppSetting.find_by!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).value
  end

  test "admin cannot save empty sks promoter ids" do
    sign_in_as(@admin)

    patch backend_settings_url, params: {
      app_setting: {
        sks_promoter_ids_text: " \n ",
        sks_organizer_notes_text: "Hinweistext",
        merge_artist_similarity_matching_enabled: "1"
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "muss mindestens eine Promoter-ID enthalten"
  end
end
