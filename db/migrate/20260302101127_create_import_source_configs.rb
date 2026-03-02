class CreateImportSourceConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :import_source_configs do |t|
      t.references :import_source, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end
  end
end
