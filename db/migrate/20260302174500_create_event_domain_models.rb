class CreateEventDomainModels < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :slug, null: false
      t.string :source_fingerprint
      t.string :title, null: false
      t.string :artist_name, null: false
      t.datetime :start_at, null: false
      t.string :venue, null: false
      t.string :city, null: false
      t.text :event_info
      t.string :badge_text
      t.string :image_url
      t.string :youtube_url
      t.string :status, null: false, default: "imported"
      t.datetime :published_at
      t.references :published_by, foreign_key: { to_table: :users }
      t.integer :completeness_score, null: false, default: 0
      t.jsonb :completeness_flags, null: false, default: []
      t.string :primary_source
      t.boolean :auto_published, null: false, default: false
      t.text :editor_notes
      t.jsonb :source_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :events, :slug, unique: true
    add_index :events, :source_fingerprint, unique: true, where: "source_fingerprint IS NOT NULL"
    add_index :events, [ :status, :start_at ]
    add_index :events, [ :published_at, :start_at ]

    create_table :event_offers do |t|
      t.references :event, null: false, foreign_key: true
      t.string :source, null: false
      t.string :source_event_id, null: false
      t.string :ticket_url
      t.string :ticket_price_text
      t.boolean :sold_out, null: false, default: false
      t.integer :priority_rank, null: false, default: 999
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :event_offers, [ :event_id, :source, :source_event_id ], unique: true
    add_index :event_offers, [ :event_id, :priority_rank ]
    add_index :event_offers, [ :source, :source_event_id ]

    create_table :genres do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :genres, :name, unique: true
    add_index :genres, :slug, unique: true

    create_table :event_genres do |t|
      t.references :event, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true

      t.timestamps
    end

    add_index :event_genres, [ :event_id, :genre_id ], unique: true

    create_table :provider_priorities do |t|
      t.string :source_type, null: false
      t.integer :priority_rank, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :provider_priorities, :source_type, unique: true

    create_table :import_run_errors do |t|
      t.references :import_run, null: false, foreign_key: true
      t.string :source_type, null: false
      t.string :external_event_id
      t.string :error_class
      t.text :message, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :import_run_errors, [ :source_type, :created_at ]

    create_table :event_change_logs do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :action, null: false
      t.jsonb :changed_fields, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :event_change_logs, [ :event_id, :created_at ]
  end
end
