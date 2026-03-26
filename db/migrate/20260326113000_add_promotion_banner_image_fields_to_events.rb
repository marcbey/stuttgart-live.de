class AddPromotionBannerImageFieldsToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :promotion_banner_image_copyright, :text
    add_column :events, :promotion_banner_image_focus_x, :float
    add_column :events, :promotion_banner_image_focus_y, :float
    add_column :events, :promotion_banner_image_zoom, :float
  end
end
