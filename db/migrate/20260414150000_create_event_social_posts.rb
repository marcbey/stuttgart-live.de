class CreateEventSocialPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :event_social_posts do |t|
      t.references :event, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :status, null: false, default: "draft"
      t.text :caption, null: false, default: ""
      t.string :target_url
      t.string :image_url
      t.string :remote_media_id
      t.string :remote_post_id
      t.datetime :approved_at
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :published_at
      t.references :published_by, foreign_key: { to_table: :users }
      t.text :error_message
      t.jsonb :payload_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :event_social_posts, [ :event_id, :platform ], unique: true
    add_index :event_social_posts, :status
  end
end
