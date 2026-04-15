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

ActiveRecord::Schema[8.1].define(version: 2026_04_15_100200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

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
    t.text "cover_image_copyright"
    t.float "cover_image_focus_x"
    t.float "cover_image_focus_y"
    t.float "cover_image_zoom"
    t.datetime "created_at", null: false
    t.boolean "promotion_banner", default: false, null: false
    t.string "promotion_banner_background_color"
    t.string "promotion_banner_cta_text"
    t.text "promotion_banner_image_copyright"
    t.float "promotion_banner_image_focus_x"
    t.float "promotion_banner_image_focus_y"
    t.float "promotion_banner_image_zoom"
    t.string "promotion_banner_kicker_text"
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
    t.index ["promotion_banner"], name: "index_blog_posts_on_unique_promotion_banner", unique: true, where: "promotion_banner"
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
    t.text "venue_address"
    t.text "venue_description"
    t.string "venue_external_url"
    t.string "youtube_link"
    t.index ["event_id"], name: "index_event_llm_enrichments_on_event_id", unique: true
    t.index ["genre"], name: "index_event_llm_enrichments_on_genre", using: :gin
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

  create_table "event_presenters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.integer "position", null: false
    t.bigint "presenter_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "position"], name: "index_event_presenters_on_event_id_and_position", unique: true
    t.index ["event_id", "presenter_id"], name: "index_event_presenters_on_event_id_and_presenter_id", unique: true
    t.index ["event_id"], name: "index_event_presenters_on_event_id"
    t.index ["presenter_id"], name: "index_event_presenters_on_presenter_id"
  end

  create_table "event_series", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "origin", null: false
    t.string "source_key"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["source_type", "source_key"], name: "index_event_series_on_source_type_and_source_key", unique: true, where: "(source_key IS NOT NULL)"
  end

  create_table "event_social_posts", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.text "caption", default: "", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "event_id", null: false
    t.string "image_url"
    t.jsonb "payload_snapshot", default: {}, null: false
    t.string "platform", null: false
    t.datetime "published_at"
    t.bigint "published_by_id"
    t.string "remote_media_id"
    t.string "remote_post_id"
    t.string "status", default: "draft", null: false
    t.string "target_url"
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_event_social_posts_on_approved_by_id"
    t.index ["event_id", "platform"], name: "index_event_social_posts_on_event_id_and_platform", unique: true
    t.index ["event_id"], name: "index_event_social_posts_on_event_id"
    t.index ["published_by_id"], name: "index_event_social_posts_on_published_by_id"
    t.index ["status"], name: "index_event_social_posts_on_status"
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
    t.string "event_series_assignment", default: "auto", null: false
    t.bigint "event_series_id"
    t.string "facebook_url"
    t.boolean "highlighted", default: false, null: false
    t.string "homepage_url"
    t.string "instagram_url"
    t.decimal "max_price", precision: 10, scale: 2
    t.decimal "min_price", precision: 10, scale: 2
    t.string "normalized_artist_name", null: false
    t.text "organizer_notes", default: "Wir bitten um Beachtung verstärkter Sicherheitsmaßnahmen\n\nWas du mitbringen darfst:\n✅ Handy, Schlüssel, Geldbeutel, Medikamente, Kleine Kosmetikartikel, kleine Taschen (maximal Größe DIN A4)\n\nWas du nicht mitbringen darfst:\n❌ Handtaschen, Rucksäcke, Helme, Behälter aller Art, Keine großen Taschen\n\nKontrollen beim Einlass:\n- Alle Besucher werden abgetastet (Bodycheck)\n- Es gibt strengere Sicherheitskontrollen als sonst\n\nDie Einhaltung dieser Regeln und Hinweise sowie ein rechtzeitiges Eintreffen helfen dabei, den Einlass so zügig wie möglich zu organisieren.\n\nWir danken für Ihr Verständnis!\n\nAltersfreigabe:\nkein Zutritt: unter 6 Jahren\nnur in Begleitung: bis 14 Jahren → Begleitformular PDF\nfrei ab 14 Jahren\n\nTelefonischer Ticketkauf:\n\nBei dieser Veranstaltung gibt es auch die Möglichkeit des telefonischen Ticketkaufes. Sie erreichen unsere Tickethotline in der Regel von Montag bis Freitag zwischen 10 und 18 Uhr unter Telefon 0711-550 660 77", null: false
    t.string "primary_source"
    t.string "promoter_id"
    t.string "promoter_name"
    t.boolean "promotion_banner", default: false, null: false
    t.string "promotion_banner_background_color"
    t.string "promotion_banner_cta_text"
    t.text "promotion_banner_image_copyright"
    t.float "promotion_banner_image_focus_x"
    t.float "promotion_banner_image_focus_y"
    t.float "promotion_banner_image_zoom"
    t.string "promotion_banner_kicker_text"
    t.datetime "published_at"
    t.bigint "published_by_id"
    t.boolean "show_organizer_notes", default: false, null: false
    t.text "sks_sold_out_message"
    t.string "slug", null: false
    t.string "source_fingerprint"
    t.jsonb "source_snapshot", default: {}, null: false
    t.datetime "start_at", null: false
    t.string "status", default: "imported", null: false
    t.string "support"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "venue_id", null: false
    t.string "youtube_url"
    t.index ["event_series_assignment"], name: "index_events_on_event_series_assignment"
    t.index ["event_series_id"], name: "index_events_on_event_series_id"
    t.index ["promoter_id", "start_at", "id"], name: "index_events_on_published_promoter_id_start_at_and_id", where: "((status)::text = 'published'::text)"
    t.index ["promoter_id"], name: "index_events_on_promoter_id"
    t.index ["promotion_banner"], name: "index_events_on_unique_promotion_banner", unique: true, where: "promotion_banner"
    t.index ["published_at", "start_at"], name: "index_events_on_published_at_and_start_at"
    t.index ["published_by_id"], name: "index_events_on_published_by_id"
    t.index ["slug"], name: "index_events_on_slug", unique: true
    t.index ["source_fingerprint"], name: "index_events_on_source_fingerprint", unique: true, where: "(source_fingerprint IS NOT NULL)"
    t.index ["start_at", "id"], name: "index_events_on_published_highlighted_start_at_and_id", where: "(((status)::text = 'published'::text) AND (highlighted = true))"
    t.index ["start_at", "id"], name: "index_events_on_published_reservix_start_at_and_id", where: "(((status)::text = 'published'::text) AND ((primary_source)::text = 'reservix'::text))"
    t.index ["start_at", "normalized_artist_name"], name: "index_events_on_start_at_and_normalized_artist_name"
    t.index ["status", "start_at"], name: "index_events_on_status_and_start_at"
    t.index ["venue_id"], name: "index_events_on_venue_id"
  end

  create_table "genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_genres_on_name", unique: true
    t.index ["slug"], name: "index_genres_on_slug", unique: true
  end

  create_table "homepage_genre_lane_configurations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "lane_slugs", default: [], null: false
    t.bigint "snapshot_id", null: false
    t.datetime "updated_at", null: false
    t.index ["snapshot_id"], name: "index_homepage_genre_lane_configurations_on_snapshot_id", unique: true
  end

  create_table "import_event_images", force: :cascade do |t|
    t.string "aspect_hint", default: "unknown", null: false
    t.datetime "cache_attempted_at"
    t.text "cache_error"
    t.string "cache_status", default: "pending", null: false
    t.datetime "cached_at"
    t.datetime "created_at", null: false
    t.string "image_type", null: false
    t.text "image_url", null: false
    t.string "import_class", null: false
    t.bigint "import_event_id", null: false
    t.integer "position", default: 0, null: false
    t.string "role", default: "gallery", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["cache_status"], name: "index_import_event_images_on_cache_status"
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

  create_table "llm_genre_grouping_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "member_genres", default: [], null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.string "slug", null: false
    t.bigint "snapshot_id", null: false
    t.datetime "updated_at", null: false
    t.index ["member_genres"], name: "index_llm_genre_grouping_groups_on_member_genres", using: :gin
    t.index ["snapshot_id", "position"], name: "index_llm_genre_grouping_groups_on_snapshot_id_and_position", unique: true
    t.index ["snapshot_id", "slug"], name: "index_llm_genre_grouping_groups_on_snapshot_id_and_slug", unique: true
    t.index ["snapshot_id"], name: "index_llm_genre_grouping_groups_on_snapshot_id"
  end

  create_table "llm_genre_grouping_snapshots", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "effective_group_count", null: false
    t.bigint "import_run_id", null: false
    t.string "model", null: false
    t.string "prompt_template_digest", null: false
    t.jsonb "raw_response", default: {}, null: false
    t.jsonb "request_payload", default: {}, null: false
    t.integer "requested_group_count", null: false
    t.uuid "snapshot_key", null: false
    t.integer "source_genres_count", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_llm_genre_grouping_snapshots_on_active_true", unique: true, where: "(active = true)"
    t.index ["import_run_id"], name: "index_llm_genre_grouping_snapshots_on_import_run_id", unique: true
    t.index ["snapshot_key"], name: "index_llm_genre_grouping_snapshots_on_snapshot_key", unique: true
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

  create_table "presenters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "external_url"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_presenters_on_name"
  end

  create_table "provider_priorities", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "priority_rank", null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["source_type"], name: "index_provider_priorities_on_source_type", unique: true
  end

  create_table "publish_attempts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.bigint "event_social_post_id", null: false
    t.datetime "finished_at"
    t.bigint "initiated_by_id"
    t.string "platform", null: false
    t.jsonb "request_snapshot", default: {}, null: false
    t.jsonb "response_snapshot", default: {}, null: false
    t.bigint "social_connection_id"
    t.bigint "social_connection_target_id"
    t.datetime "started_at", null: false
    t.string "status", default: "started", null: false
    t.datetime "updated_at", null: false
    t.index ["event_social_post_id", "created_at"], name: "index_publish_attempts_on_event_social_post_id_and_created_at"
    t.index ["event_social_post_id"], name: "index_publish_attempts_on_event_social_post_id"
    t.index ["initiated_by_id"], name: "index_publish_attempts_on_initiated_by_id"
    t.index ["platform"], name: "index_publish_attempts_on_platform"
    t.index ["social_connection_id"], name: "index_publish_attempts_on_social_connection_id"
    t.index ["social_connection_target_id"], name: "index_publish_attempts_on_social_connection_target_id"
    t.index ["status"], name: "index_publish_attempts_on_status"
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

  create_table "social_connection_targets", force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name"
    t.bigint "parent_target_id"
    t.boolean "selected", default: false, null: false
    t.bigint "social_connection_id", null: false
    t.string "status", default: "available", null: false
    t.string "target_type", null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["parent_target_id"], name: "index_social_connection_targets_on_parent_target_id"
    t.index ["social_connection_id", "target_type", "external_id"], name: "index_social_connection_targets_on_connection_and_target", unique: true
    t.index ["social_connection_id", "target_type", "selected"], name: "index_social_connection_targets_on_connection_type_selected"
    t.index ["social_connection_id"], name: "index_social_connection_targets_on_social_connection_id"
    t.index ["status"], name: "index_social_connection_targets_on_status"
  end

  create_table "social_connections", force: :cascade do |t|
    t.string "auth_mode", null: false
    t.datetime "connected_at"
    t.string "connection_status", default: "disconnected", null: false
    t.datetime "created_at", null: false
    t.string "external_user_id"
    t.jsonb "granted_scopes", default: [], null: false
    t.text "last_error"
    t.datetime "last_refresh_at"
    t.datetime "last_token_check_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "provider", null: false
    t.datetime "reauth_required_at"
    t.datetime "updated_at", null: false
    t.text "user_access_token"
    t.datetime "user_token_expires_at"
    t.index ["connection_status"], name: "index_social_connections_on_connection_status"
    t.index ["provider"], name: "index_social_connections_on_provider", unique: true
  end

  create_table "static_pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "intro"
    t.string "kicker"
    t.string "slug", null: false
    t.string "system_key"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_static_pages_on_slug", unique: true
    t.index ["system_key"], name: "index_static_pages_on_system_key", unique: true
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

  create_table "venues", force: :cascade do |t|
    t.text "address"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "external_url"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text) gin_trgm_ops", name: "index_venues_on_lower_name_trgm", using: :gin
    t.index "lower((name)::text)", name: "index_venues_on_lower_name", unique: true
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
  add_foreign_key "event_presenters", "events"
  add_foreign_key "event_presenters", "presenters"
  add_foreign_key "event_social_posts", "events"
  add_foreign_key "event_social_posts", "users", column: "approved_by_id"
  add_foreign_key "event_social_posts", "users", column: "published_by_id"
  add_foreign_key "events", "event_series"
  add_foreign_key "events", "users", column: "published_by_id"
  add_foreign_key "events", "venues"
  add_foreign_key "homepage_genre_lane_configurations", "llm_genre_grouping_snapshots", column: "snapshot_id"
  add_foreign_key "import_run_errors", "import_runs"
  add_foreign_key "import_runs", "import_sources"
  add_foreign_key "import_source_configs", "import_sources"
  add_foreign_key "llm_genre_grouping_groups", "llm_genre_grouping_snapshots", column: "snapshot_id"
  add_foreign_key "llm_genre_grouping_snapshots", "import_runs"
  add_foreign_key "login_attempts", "users"
  add_foreign_key "publish_attempts", "event_social_posts"
  add_foreign_key "publish_attempts", "social_connection_targets"
  add_foreign_key "publish_attempts", "social_connections"
  add_foreign_key "publish_attempts", "users", column: "initiated_by_id"
  add_foreign_key "raw_event_imports", "import_sources"
  add_foreign_key "sessions", "users"
  add_foreign_key "social_connection_targets", "social_connection_targets", column: "parent_target_id"
  add_foreign_key "social_connection_targets", "social_connections"
end
