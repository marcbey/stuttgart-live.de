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

ActiveRecord::Schema[8.1].define(version: 2026_03_19_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.jsonb "value", default: [], null: false
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "blog_posts", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "author_name"
    t.datetime "created_at", null: false
    t.datetime "published_at"
    t.bigint "published_by_id"
    t.string "slug", null: false
    t.string "source_identifier"
    t.string "source_url"
    t.string "status", default: "draft", null: false
    t.text "teaser", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.jsonb "youtube_video_urls", default: [], null: false
    t.index ["author_id"], name: "index_blog_posts_on_author_id"
    t.index ["published_by_id"], name: "index_blog_posts_on_published_by_id"
    t.index ["slug"], name: "index_blog_posts_on_slug", unique: true
    t.index ["source_identifier"], name: "index_blog_posts_on_source_identifier", unique: true
    t.index ["status", "published_at"], name: "index_blog_posts_on_status_and_published_at"
  end

  create_table "event_change_logs", force: :cascade do |t|
    t.string "action", null: false
    t.jsonb "changed_fields", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["event_id", "created_at"], name: "index_event_change_logs_on_event_id_and_created_at"
    t.index ["event_id"], name: "index_event_change_logs_on_event_id"
    t.index ["user_id"], name: "index_event_change_logs_on_user_id"
  end

  create_table "event_genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "genre_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "genre_id"], name: "index_event_genres_on_event_id_and_genre_id", unique: true
    t.index ["event_id"], name: "index_event_genres_on_event_id"
    t.index ["genre_id"], name: "index_event_genres_on_genre_id"
  end

  create_table "event_images", force: :cascade do |t|
    t.string "alt_text"
    t.decimal "card_focus_x", precision: 5, scale: 2, default: "50.0", null: false
    t.decimal "card_focus_y", precision: 5, scale: 2, default: "50.0", null: false
    t.decimal "card_zoom", precision: 5, scale: 2, default: "100.0", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "grid_variant"
    t.string "purpose", null: false
    t.text "sub_text"
    t.datetime "updated_at", null: false
    t.index ["event_id", "grid_variant"], name: "index_event_images_on_unique_grid_variant_per_event", unique: true, where: "((purpose)::text = 'grid_tile'::text)"
    t.index ["event_id", "purpose"], name: "index_event_images_on_event_id_and_purpose"
    t.index ["event_id", "purpose"], name: "index_event_images_on_unique_detail_hero_per_event", unique: true, where: "((purpose)::text = 'detail_hero'::text)"
    t.index ["event_id"], name: "index_event_images_on_event_id"
  end

  create_table "event_llm_enrichments", force: :cascade do |t|
    t.text "artist_description"
    t.datetime "created_at", null: false
    t.text "event_description"
    t.bigint "event_id", null: false
    t.string "facebook_link"
    t.jsonb "genre", default: [], null: false
    t.string "homepage_link"
    t.string "instagram_link"
    t.string "model", null: false
    t.string "prompt_version", null: false
    t.jsonb "raw_response", default: {}, null: false
    t.bigint "source_run_id", null: false
    t.datetime "updated_at", null: false
    t.string "venue"
    t.text "venue_description"
    t.string "youtube_link"
    t.index ["event_id"], name: "index_event_llm_enrichments_on_event_id", unique: true
    t.index ["source_run_id"], name: "index_event_llm_enrichments_on_source_run_id"
  end

  create_table "event_offers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "priority_rank", default: 999, null: false
    t.boolean "sold_out", default: false, null: false
    t.string "source", null: false
    t.string "source_event_id", null: false
    t.string "ticket_price_text"
    t.string "ticket_url"
    t.datetime "updated_at", null: false
    t.index ["event_id", "priority_rank"], name: "index_event_offers_on_event_id_and_priority_rank"
    t.index ["event_id", "source", "source_event_id"], name: "index_event_offers_on_event_id_and_source_and_source_event_id", unique: true
    t.index ["event_id"], name: "index_event_offers_on_event_id"
    t.index ["source", "source_event_id"], name: "index_event_offers_on_source_and_source_event_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "artist_name", null: false
    t.boolean "auto_published", default: false, null: false
    t.string "badge_text"
    t.string "city"
    t.jsonb "completeness_flags", default: [], null: false
    t.integer "completeness_score", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "doors_at"
    t.text "editor_notes"
    t.text "event_info"
    t.string "facebook_url"
    t.boolean "highlighted", default: false, null: false
    t.string "homepage_url"
    t.string "instagram_url"
    t.decimal "max_price", precision: 10, scale: 2
    t.decimal "min_price", precision: 10, scale: 2
    t.string "normalized_artist_name", null: false
    t.text "organizer_notes", default: "Wir bitten um Beachtung verstärkter Sicherheitsmaßnahmen\nVerbot von Handtaschen, Rucksäcken und Helmen\nZusätzliche verschärfte Kontrollen und Bodychecks\nSämtliche Besucher werden Bodychecks unterzogen. Taschen, Rucksäcke und Handtaschen sowie Helme und Behältnisse aller Art sind verboten.\nDie Zuschauer werden ausdrücklich gebeten, auf deren Mitbringen zu verzichten, und sich ausschließlich auf wirklich notwendige Utensilien wie Handys, Schlüsselbund und Portemonnaies sowie Medikamente oder Kosmetika in Gürteltaschen oder Kosmetiktäschchen bis zu einer maximalen Größe von Din A4 zu beschränken.\nDie Einhaltung dieser Regeln und Hinweise sowie ein rechtzeitiges Eintreffen helfen dabei, den Einlass so zügig wie möglich zu organisieren.\n\nWir danken für Ihr Verständnis!\n\nAltersfreigabe:\nkein Zutritt: unter 6 Jahren\nnur in Begleitung: bis 14 Jahren (Das Begleitformular findest Du HIER)\nfrei ab 14 Jahren\n\nTelefonischer Ticketkauf:\n\nBei dieser Veranstaltung gibt es auch die Möglichkeit des telefonischen Ticketkaufes. Sie erreichen unsere Tickethotline in der Regel von Montag bis Freitag zwischen 10 und 18 Uhr unter Telefon 0711-550 660 77\n", null: false
    t.string "primary_source"
    t.string "promoter_id"
    t.datetime "published_at"
    t.bigint "published_by_id"
    t.boolean "show_organizer_notes", default: false, null: false
    t.string "slug", null: false
    t.string "source_fingerprint"
    t.jsonb "source_snapshot", default: {}, null: false
    t.datetime "start_at", null: false
    t.string "status", default: "imported", null: false
    t.string "support"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "venue", null: false
    t.string "youtube_url"
    t.index ["promoter_id", "start_at", "id"], name: "index_events_on_published_promoter_id_start_at_and_id", where: "((status)::text = 'published'::text)"
    t.index ["promoter_id"], name: "index_events_on_promoter_id"
    t.index ["published_at", "start_at"], name: "index_events_on_published_at_and_start_at"
    t.index ["published_by_id"], name: "index_events_on_published_by_id"
    t.index ["slug"], name: "index_events_on_slug", unique: true
    t.index ["source_fingerprint"], name: "index_events_on_source_fingerprint", unique: true, where: "(source_fingerprint IS NOT NULL)"
    t.index ["start_at", "id"], name: "index_events_on_published_highlighted_start_at_and_id", where: "(((status)::text = 'published'::text) AND (highlighted = true))"
    t.index ["start_at", "id"], name: "index_events_on_published_reservix_start_at_and_id", where: "(((status)::text = 'published'::text) AND ((primary_source)::text = 'reservix'::text))"
    t.index ["start_at", "normalized_artist_name"], name: "index_events_on_start_at_and_normalized_artist_name"
    t.index ["status", "start_at"], name: "index_events_on_status_and_start_at"
  end

  create_table "genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_genres_on_name", unique: true
    t.index ["slug"], name: "index_genres_on_slug", unique: true
  end

  create_table "import_event_images", force: :cascade do |t|
    t.string "aspect_hint", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.string "image_type", null: false
    t.text "image_url", null: false
    t.string "import_class", null: false
    t.bigint "import_event_id", null: false
    t.integer "position", default: 0, null: false
    t.string "role", default: "gallery", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["import_class", "import_event_id", "source", "image_type", "image_url"], name: "index_import_event_images_on_unique_image_per_owner", unique: true
    t.index ["import_class", "import_event_id"], name: "index_import_event_images_on_class_and_event"
  end

  create_table "import_run_errors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_class"
    t.string "external_event_id"
    t.bigint "import_run_id", null: false
    t.text "message", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["import_run_id"], name: "index_import_run_errors_on_import_run_id"
    t.index ["source_type", "created_at"], name: "index_import_run_errors_on_source_type_and_created_at"
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

  create_table "login_attempts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address"
    t.string "ip_address"
    t.string "outcome", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.index ["created_at"], name: "index_login_attempts_on_created_at"
    t.index ["email_address", "created_at"], name: "index_login_attempts_on_email_address_and_created_at"
    t.index ["outcome", "created_at"], name: "index_login_attempts_on_outcome_and_created_at"
    t.index ["user_id"], name: "index_login_attempts_on_user_id"
  end

  create_table "newsletter_subscribers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.text "mailchimp_error_message"
    t.datetime "mailchimp_last_synced_at"
    t.string "mailchimp_member_id"
    t.string "mailchimp_status", default: "pending", null: false
    t.string "source", default: "homepage", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_newsletter_subscribers_on_lower_email", unique: true
    t.index ["mailchimp_member_id"], name: "index_newsletter_subscribers_on_mailchimp_member_id"
    t.index ["mailchimp_status"], name: "index_newsletter_subscribers_on_mailchimp_status"
  end

  create_table "provider_priorities", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "priority_rank", null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["source_type"], name: "index_provider_priorities_on_source_type", unique: true
  end

  create_table "raw_event_imports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "detail_payload", default: {}, null: false
    t.string "import_event_type", null: false
    t.bigint "import_source_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "source_identifier", null: false
    t.datetime "updated_at", null: false
    t.index ["import_event_type", "created_at"], name: "index_raw_event_imports_on_import_event_type_and_created_at"
    t.index ["import_event_type", "source_identifier", "created_at"], name: "index_raw_event_imports_on_type_identifier_created_at"
    t.index ["import_source_id"], name: "index_raw_event_imports_on_import_source_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.integer "failed_login_attempts", default: 0, null: false
    t.datetime "last_failed_login_at"
    t.datetime "locked_until"
    t.string "name"
    t.string "password_digest", null: false
    t.string "role", default: "editor", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["locked_until"], name: "index_users_on_locked_until"
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "blog_posts", "users", column: "author_id"
  add_foreign_key "blog_posts", "users", column: "published_by_id"
  add_foreign_key "event_change_logs", "events"
  add_foreign_key "event_change_logs", "users"
  add_foreign_key "event_genres", "events"
  add_foreign_key "event_genres", "genres"
  add_foreign_key "event_images", "events"
  add_foreign_key "event_llm_enrichments", "events"
  add_foreign_key "event_llm_enrichments", "import_runs", column: "source_run_id"
  add_foreign_key "event_offers", "events"
  add_foreign_key "events", "users", column: "published_by_id"
  add_foreign_key "import_run_errors", "import_runs"
  add_foreign_key "import_runs", "import_sources"
  add_foreign_key "import_source_configs", "import_sources"
  add_foreign_key "login_attempts", "users"
  add_foreign_key "raw_event_imports", "import_sources"
  add_foreign_key "sessions", "users"
end
