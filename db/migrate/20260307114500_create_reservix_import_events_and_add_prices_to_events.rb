class CreateReservixImportEventsAndAddPricesToEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :reservix_import_events do |t|
      t.references :import_source, null: false, foreign_key: true
      t.string :external_event_id, null: false
      t.date :concert_date, null: false
      t.string :concert_date_label, null: false
      t.string :city, null: false
      t.string :venue_name, null: false
      t.string :venue_label, null: false
      t.string :title, null: false
      t.string :artist_name, null: false
      t.string :organizer_name
      t.decimal :min_price, precision: 10, scale: 2
      t.decimal :max_price, precision: 10, scale: 2
      t.string :ticket_url
      t.string :source_payload_hash, null: false
      t.jsonb :dump_payload, null: false, default: {}
      t.jsonb :detail_payload, null: false, default: {}
      t.boolean :is_active, null: false, default: true
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    add_index :reservix_import_events, [ :import_source_id, :external_event_id ], unique: true, name: "index_reservix_import_events_on_source_and_external_id"
    add_index :reservix_import_events, :is_active

    add_column :events, :min_price, :decimal, precision: 10, scale: 2
    add_column :events, :max_price, :decimal, precision: 10, scale: 2
  end
end
