# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_02_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "easyticket_import_events", force: :cascade do |t|
    t.string "artist_name", null: false
    t.string "city", null: false
    t.date "concert_date", null: false
    t.string "concert_date_label", null: false
    t.datetime "created_at", null: false
    t.jsonb "detail_payload", default: {}, null: false
    t.jsonb "dump_payload", default: {}, null: false
    t.string "external_event_id", null: false
    t.datetime "first_seen_at", null: false
    t.string "image_url"
    t.bigint "import_source_id", null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "last_seen_at", null: false
    t.string "source_payload_hash", null: false
    t.string "ticket_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "venue_label", null: false
    t.string "venue_name", null: false
    t.index ["import_source_id", "external_event_id", "concert_date"], name: "idx_easyticket_import_events_unique_event", unique: true
    t.index ["import_source_id", "is_active", "concert_date"], name: "idx_easyticket_import_events_active_by_date"
    t.index ["import_source_id"], name: "index_easyticket_import_events_on_import_source_id"
    t.index ["source_payload_hash"], name: "index_easyticket_import_events_on_source_payload_hash"
  end

  create_table "import_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "failed_count", default: 0, null: false
    t.integer "fetched_count", default: 0, null: false
    t.integer "filtered_count", default: 0, null: false
    t.datetime "finished_at"
    t.bigint "import_source_id", null: false
    t.integer "imported_count", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "source_type", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.integer "upserted_count", default: 0, null: false
    t.index ["import_source_id", "created_at"], name: "index_import_runs_on_import_source_id_and_created_at"
    t.index ["import_source_id"], name: "index_import_runs_on_import_source_id"
    t.index ["source_type", "created_at"], name: "index_import_runs_on_source_type_and_created_at"
  end

  create_table "import_source_configs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "import_source_id", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["import_source_id"], name: "index_import_source_configs_on_import_source_id", unique: true
  end

  create_table "import_sources", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["source_type"], name: "index_import_sources_on_source_type", unique: true
  end

  add_foreign_key "easyticket_import_events", "import_sources"
  add_foreign_key "import_runs", "import_sources"
  add_foreign_key "import_source_configs", "import_sources"
end
