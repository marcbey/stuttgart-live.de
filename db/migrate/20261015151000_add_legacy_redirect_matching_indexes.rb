class AddLegacyRedirectMatchingIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    [ [ :events, :artist_name ], [ :blog_posts, :title ], [ :static_pages, :title ] ].each do |table, column|
      add_index table, "LOWER(#{column}) gin_trgm_ops", using: :gin,
        name: "index_#{table}_on_legacy_#{column}_trgm", algorithm: :concurrently, if_not_exists: true
    end
    add_index :events, :source_snapshot, using: :gin, name: "index_events_on_legacy_source_snapshot", algorithm: :concurrently, if_not_exists: true
  end

  def down
    [ [ :events, :artist_name ], [ :blog_posts, :title ], [ :static_pages, :title ] ].each do |table, column|
      remove_index table, name: "index_#{table}_on_legacy_#{column}_trgm", algorithm: :concurrently, if_exists: true
    end
    remove_index :events, name: "index_events_on_legacy_source_snapshot", algorithm: :concurrently, if_exists: true
  end
end
