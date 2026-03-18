class CreateEventLlmEnrichments < ActiveRecord::Migration[8.1]
  def change
    create_table :event_llm_enrichments do |t|
      t.references :event, null: false, foreign_key: true, index: { unique: true }
      t.references :source_run, null: false, foreign_key: { to_table: :import_runs }
      t.jsonb :genre, default: [], null: false
      t.string :venue
      t.text :artist_description
      t.text :event_description
      t.text :venue_description
      t.string :youtube_link
      t.string :instagram_link
      t.string :homepage_link
      t.string :facebook_link
      t.string :model, null: false
      t.string :prompt_version, null: false
      t.jsonb :raw_response, default: {}, null: false
      t.timestamps
    end
  end
end
