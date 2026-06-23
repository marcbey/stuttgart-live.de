class AddPromotionBannerTitleAndTextToBlogPostsAndEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :blog_posts, :promotion_banner_title, :string
    add_column :blog_posts, :promotion_banner_text, :string
    add_column :events, :promotion_banner_title, :string
    add_column :events, :promotion_banner_text, :string
  end
end
