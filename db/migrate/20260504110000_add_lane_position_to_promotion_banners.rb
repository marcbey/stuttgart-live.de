class AddLanePositionToPromotionBanners < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :promotion_banner_lane_position, :integer
    add_column :blog_posts, :promotion_banner_lane_position, :integer

    execute "UPDATE events SET promotion_banner_lane_position = 1 WHERE promotion_banner = TRUE"
    execute "UPDATE blog_posts SET promotion_banner_lane_position = 1 WHERE promotion_banner = TRUE"

    remove_index :events, name: "index_events_on_unique_promotion_banner"
    remove_index :blog_posts, name: "index_blog_posts_on_unique_promotion_banner"

    add_index :events,
              [ :promotion_banner, :promotion_banner_lane_position, :start_at, :id ],
              name: "index_events_on_promotion_banner_lane_position",
              where: "promotion_banner"
    add_index :blog_posts,
              [ :promotion_banner, :promotion_banner_lane_position, :published_at, :id ],
              name: "index_blog_posts_on_promotion_banner_lane_position",
              where: "promotion_banner"
  end

  def down
    remove_index :blog_posts, name: "index_blog_posts_on_promotion_banner_lane_position"
    remove_index :events, name: "index_events_on_promotion_banner_lane_position"

    add_index :blog_posts,
              :promotion_banner,
              name: "index_blog_posts_on_unique_promotion_banner",
              unique: true,
              where: "promotion_banner"
    add_index :events,
              :promotion_banner,
              name: "index_events_on_unique_promotion_banner",
              unique: true,
              where: "promotion_banner"

    remove_column :blog_posts, :promotion_banner_lane_position
    remove_column :events, :promotion_banner_lane_position
  end
end
