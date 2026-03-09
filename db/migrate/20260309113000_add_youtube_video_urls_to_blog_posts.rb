class AddYoutubeVideoUrlsToBlogPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :blog_posts, :youtube_video_urls, :jsonb, null: false, default: []
  end
end
