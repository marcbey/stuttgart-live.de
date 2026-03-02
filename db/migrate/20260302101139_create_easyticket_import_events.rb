class CreateEasyticketImportEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :easyticket_import_events do |t|
      t.references :import_source, null: false, foreign_key: true
      t.string :external_event_id, null: false
      t.date :concert_date, null: false
      t.string :city, null: false
      t.string :venue_name, null: false
      t.string :title, null: false
      t.string :artist_name, null: false
      t.string :concert_date_label, null: false
      t.string :venue_label, null: false
      t.jsonb :dump_payload, null: false, default: {}
      t.jsonb :detail_payload, null: false, default: {}
      t.string :ticket_url
      t.string :image_url
      t.boolean :is_active, null: false, default: true
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.string :source_payload_hash, null: false

      t.timestamps
    end

    add_index :easyticket_import_events, [ :import_source_id, :external_event_id, :concert_date ],
      unique: true,
      name: "idx_easyticket_import_events_unique_event"
    add_index :easyticket_import_events, [ :import_source_id, :is_active, :concert_date ],
      name: "idx_easyticket_import_events_active_by_date"
    add_index :easyticket_import_events, :source_payload_hash
  end
end
