class AddPromotionBannerSliderTextHiddenToBlogPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :blog_posts, :promotion_banner_slider_text_hidden, :boolean, null: false, default: false
  end
end
