require "test_helper"

class Backend::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)
    @editor = users(:one)
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "admin can edit settings" do
    sign_in_as(@admin)
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: %w[10135 10136 382])

    get edit_backend_settings_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Einstellungen"
    assert_includes response.body, "SKS Promoter IDs"
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
        sks_promoter_ids_text: "900\n901, 902"
      }
    }

    assert_redirected_to edit_backend_settings_url
    assert_equal %w[900 901 902], AppSetting.sks_promoter_ids
    assert_equal %w[900 901 902], AppSetting.find_by!(key: AppSetting::SKS_PROMOTER_IDS_KEY).value
  end

  test "admin cannot save empty sks promoter ids" do
    sign_in_as(@admin)

    patch backend_settings_url, params: {
      app_setting: {
        sks_promoter_ids_text: " \n "
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "muss mindestens eine Promoter-ID enthalten"
  end
end
