class CreateLegacyRedirects < ActiveRecord::Migration[8.1]
  def change
    create_table :legacy_redirects do |t|
      t.string :source_path, null: false
      t.string :source_kind, null: false, default: "page"
      t.jsonb :source_metadata, null: false, default: {}
      t.string :status, null: false, default: "unresolved"
      t.string :origin, null: false, default: "automatic"
      t.references :target, polymorphic: true
      t.string :target_path
      t.string :match_reason
      t.decimal :score
      t.datetime :checked_at
      t.string :resolution_version
      t.timestamps
    end
    add_index :legacy_redirects, :source_path, unique: true
    add_index :legacy_redirects, [ :status, :origin ]
  end
end
