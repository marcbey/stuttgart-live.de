class AddPromotionBannerBackgroundColorToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :promotion_banner_background_color, :string unless column_exists?(:events, :promotion_banner_background_color)
  end
end
