class CreateImportSources < ActiveRecord::Migration[8.1]
  def change
    create_table :import_sources do |t|
      t.string :name, null: false
      t.string :source_type, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :import_sources, :source_type, unique: true
  end
end
