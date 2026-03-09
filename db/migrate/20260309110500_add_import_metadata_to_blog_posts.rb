class AddImportMetadataToBlogPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :blog_posts, :author_name, :string
    add_column :blog_posts, :source_identifier, :string
    add_column :blog_posts, :source_url, :string

    add_index :blog_posts, :source_identifier, unique: true
  end
end
