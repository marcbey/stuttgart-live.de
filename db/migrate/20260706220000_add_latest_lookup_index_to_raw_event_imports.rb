class AddLatestLookupIndexToRawEventImports < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :raw_event_imports,
      [ :import_event_type, :source_identifier, :created_at, :id ],
      algorithm: :concurrently,
      if_not_exists: true,
      order: { created_at: :desc, id: :desc },
      name: "idx_raw_event_imports_latest_lookup"
  end

  def down
    remove_index :raw_event_imports,
      algorithm: :concurrently,
      if_exists: true,
      name: "idx_raw_event_imports_latest_lookup"
  end
end
