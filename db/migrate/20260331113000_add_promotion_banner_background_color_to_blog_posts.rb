class AddPromotionBannerBackgroundColorToBlogPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :blog_posts, :promotion_banner_background_color, :string unless column_exists?(:blog_posts, :promotion_banner_background_color)
  end
end
