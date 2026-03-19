class AddImageEditorFieldsToBlogPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :blog_posts, :cover_image_copyright, :text
    add_column :blog_posts, :cover_image_focus_x, :float
    add_column :blog_posts, :cover_image_focus_y, :float
    add_column :blog_posts, :cover_image_zoom, :float
    add_column :blog_posts, :promotion_banner_image_copyright, :text
    add_column :blog_posts, :promotion_banner_image_focus_x, :float
    add_column :blog_posts, :promotion_banner_image_focus_y, :float
    add_column :blog_posts, :promotion_banner_image_zoom, :float
  end
end
