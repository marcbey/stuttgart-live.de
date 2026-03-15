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

  test "returns empty sks promoter ids when nothing is configured" do
    assert_equal [], AppSetting.sks_promoter_ids
  end

  test "requires at least one configured sks promoter id" do
    setting = AppSetting.new(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [])

    assert_not setting.valid?
    assert_includes setting.errors[:value], "muss mindestens eine Promoter-ID enthalten"
  end
end
