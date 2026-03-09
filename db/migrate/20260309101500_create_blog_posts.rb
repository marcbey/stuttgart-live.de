class CreateBlogPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :blog_posts do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :teaser, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :published_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :blog_posts, :slug, unique: true
    add_index :blog_posts, [ :status, :published_at ]
  end
end
