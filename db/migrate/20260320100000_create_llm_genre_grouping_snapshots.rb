class CreateLlmGenreGroupingSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_genre_grouping_snapshots do |t|
      t.references :import_run, null: false, foreign_key: true, index: { unique: true }
      t.uuid :snapshot_key, null: false
      t.boolean :active, null: false, default: false
      t.integer :requested_group_count, null: false
      t.integer :effective_group_count, null: false
      t.integer :source_genres_count, null: false
      t.string :model, null: false
      t.string :prompt_template_digest, null: false
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :raw_response, null: false, default: {}
      t.timestamps
    end

    add_index :llm_genre_grouping_snapshots, :snapshot_key, unique: true
    add_index :llm_genre_grouping_snapshots, :active, unique: true, where: "active = TRUE", name: "index_llm_genre_grouping_snapshots_on_active_true"

    create_table :llm_genre_grouping_groups do |t|
      t.references :snapshot, null: false, foreign_key: { to_table: :llm_genre_grouping_snapshots }
      t.integer :position, null: false
      t.string :name, null: false
      t.string :slug, null: false
      t.jsonb :member_genres, null: false, default: []
      t.timestamps
    end

    add_index :llm_genre_grouping_groups, [ :snapshot_id, :position ], unique: true
    add_index :llm_genre_grouping_groups, [ :snapshot_id, :slug ], unique: true
    add_index :llm_genre_grouping_groups, :member_genres, using: :gin
    add_index :event_llm_enrichments, :genre, using: :gin
  end
end
