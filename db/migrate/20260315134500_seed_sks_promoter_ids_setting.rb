class SeedSksPromoterIdsSetting < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  SKS_PROMOTER_IDS = %w[10135 10136 382].freeze

  def up
    AppSettingMigration.find_or_create_by!(key: "sks_promoter_ids") do |setting|
      setting.value = SKS_PROMOTER_IDS
    end
  end

  def down
    AppSettingMigration.where(key: "sks_promoter_ids", value: SKS_PROMOTER_IDS).delete_all
  end
end
