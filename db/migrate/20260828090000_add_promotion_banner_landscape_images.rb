class AddPromotionBannerLandscapeImages < ActiveRecord::Migration[8.0]
  def change
    change_table :events, bulk: true do |t|
      t.text :promotion_banner_landscape_image_copyright
      t.float :promotion_banner_landscape_image_focus_x, default: 50.0, null: false
      t.float :promotion_banner_landscape_image_focus_y, default: 50.0, null: false
      t.float :promotion_banner_landscape_image_zoom, default: 100.0, null: false
    end

    change_table :blog_posts, bulk: true do |t|
      t.text :promotion_banner_landscape_image_copyright
      t.float :promotion_banner_landscape_image_focus_x, default: 50.0, null: false
      t.float :promotion_banner_landscape_image_focus_y, default: 50.0, null: false
      t.float :promotion_banner_landscape_image_zoom, default: 100.0, null: false
    end
  end
end
