class AddPromotionBannerCtaColorToBlogPostsAndEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :blog_posts, :promotion_banner_cta_color, :string unless column_exists?(:blog_posts, :promotion_banner_cta_color)
    add_column :events, :promotion_banner_cta_color, :string unless column_exists?(:events, :promotion_banner_cta_color)
  end
end
