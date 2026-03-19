class AddPromotionBannerToBlogPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :blog_posts, :promotion_banner, :boolean, null: false, default: false
    add_index :blog_posts, :promotion_banner, unique: true, where: "promotion_banner", name: "index_blog_posts_on_unique_promotion_banner"
  end
end
