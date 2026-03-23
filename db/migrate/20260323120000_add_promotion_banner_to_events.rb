class AddPromotionBannerToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :promotion_banner, :boolean, null: false, default: false
    add_column :events, :promotion_banner_kicker_text, :string
    add_column :events, :promotion_banner_cta_text, :string

    add_index :events,
              :promotion_banner,
              unique: true,
              where: "promotion_banner",
              name: "index_events_on_unique_promotion_banner"
  end
end
