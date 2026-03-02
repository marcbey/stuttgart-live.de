class CreateImportRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :import_runs do |t|
      t.references :import_source, null: false, foreign_key: true
      t.string :source_type, null: false
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :fetched_count, null: false, default: 0
      t.integer :filtered_count, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :import_runs, [ :source_type, :created_at ]
    add_index :import_runs, [ :import_source_id, :created_at ]
  end
end
