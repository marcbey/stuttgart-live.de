class AddCacheFieldsToImportEventImages < ActiveRecord::Migration[8.1]
  def change
    add_column :import_event_images, :cache_status, :string, null: false, default: "pending"
    add_column :import_event_images, :cache_attempted_at, :datetime
    add_column :import_event_images, :cached_at, :datetime
    add_column :import_event_images, :cache_error, :text

    add_index :import_event_images, :cache_status
  end
end
