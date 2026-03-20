class AddPromotionBannerCopyFieldsToBlogPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :blog_posts, :promotion_banner_kicker_text, :string
    add_column :blog_posts, :promotion_banner_cta_text, :string
  end
end
