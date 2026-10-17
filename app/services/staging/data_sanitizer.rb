require "bcrypt"
require "securerandom"
require "json"

module Staging
  # This service never instantiates models or decrypts copied production tokens.
  class DataSanitizer
    Error = Class.new(StandardError)
    DATABASE = "stuttgart_live_de_staging".freeze
    EMPTY_TABLES = %w[publish_attempts event_social_posts social_connection_targets social_connections sessions login_attempts
      newsletter_consent_events newsletter_subscriber_interests newsletter_subscribers event_change_logs import_run_errors raw_event_imports].freeze
    PUBLIC_SETTINGS = %w[sks_promoter_ids sks_organizer_notes merge_artist_similarity_matching_enabled venue_duplicate_mappings
      homepage_genre_lane_slugs homepage_genre_tag_cloud_enabled homepage_highlight_video llm_enrichment_model
      llm_enrichment_temperature llm_enrichment_web_search_provider].freeze
    DISABLED_SETTINGS = %w[daily_raw_import_enabled daily_merge_import_enabled daily_llm_enrichment_enabled].freeze

    def self.call(connection:)
      new(connection:).call
    end

    def initialize(connection:)
      @connection = connection
      @counts = {}
    end

    def call
      validate_target!
      @connection.transaction do
        remove_private_records
        sanitize_import_images
        sanitize_users
        update("blog_posts", "author_name = 'Redaktion Staging'")
        update("events", "editor_notes = NULL, source_snapshot = '{}'::jsonb")
        update("event_offers", "metadata = jsonb_strip_nulls(jsonb_build_object('availability_status', metadata->'availability_status'))")
        update("event_llm_enrichments", "raw_response = '{}'::jsonb")
        replace_import_history
        update("import_sources", "active = FALSE, name = 'Staging ' || source_type, settings = '{}'::jsonb")
        update("import_source_configs", "settings = '{}'::jsonb")
        update("newsletter_interests", "mailjet_segment_id = NULL")
        update("newsletter_issues", <<~SQL.squish)
          status = 'draft', title = 'Staging Newsletter ' || id, subject = 'Staging Newsletter',
          intro = NULL, preheader = NULL, header_title = NULL, jump_menu_title = NULL,
          team_tip_name = NULL, team_tip_role = NULL, team_tip_text = NULL, team_tip_profile_key = NULL, team_tip_image_url = NULL,
          mailjet_campaign_draft_id = NULL, mailjet_campaign_id = NULL, mailjet_error_message = NULL,
          mailjet_last_synced_at = NULL, sent_at = NULL, test_sent_at = NULL, sent_by_id = NULL
        SQL
        update("newsletter_issue_items", "headline_override = NULL, teaser_override = NULL")
        # Mappings remain; copied crawl diagnostics/evidence may contain private raw HTML.
        update("legacy_redirects", "source_metadata = '{}'::jsonb")
        sanitize_settings
        sanitize_blob_metadata
        verify!
        @counts
      end
    end

    def verify!(admin_id: nil)
      validate_target!
      EMPTY_TABLES.each { |table| assert_zero("SELECT COUNT(*) FROM #{table}") }
      assert_zero(<<~SQL)
        SELECT COUNT(*) FROM import_event_images images
        WHERE images.import_class <> 'Event'
          OR NOT EXISTS (SELECT 1 FROM events WHERE events.id = images.import_event_id)
          OR to_jsonb(images)->>'cache_error' IS NOT NULL OR to_jsonb(images)->>'cache_attempted_at' IS NOT NULL
          OR to_jsonb(images)->>'cached_at' IS NOT NULL OR COALESCE(to_jsonb(images)->>'cache_status', 'pending') <> 'pending'
      SQL
      admin_clause = admin_id ? " AND id <> #{Integer(admin_id)}" : ""
      assert_zero("SELECT COUNT(*) FROM users WHERE (email_address <> 'user-' || id || '@example.invalid' OR name IS DISTINCT FROM 'Benutzer ' || id OR role <> 'editor' OR failed_login_attempts <> 0 OR locked_until IS NOT NULL)#{admin_clause}")
      assert_zero("SELECT COUNT(*) FROM users WHERE role = 'admin'#{admin_clause}")
      assert_zero("SELECT COUNT(*) FROM events WHERE editor_notes IS NOT NULL OR source_snapshot <> '{}'::jsonb")
      assert_zero("SELECT COUNT(*) FROM event_llm_enrichments WHERE raw_response <> '{}'::jsonb")
      assert_zero("SELECT COUNT(*) FROM import_sources WHERE active OR settings <> '{}'::jsonb")
      assert_zero("SELECT COUNT(*) FROM import_source_configs WHERE settings <> '{}'::jsonb")
      assert_zero("SELECT COUNT(*) FROM newsletter_issues WHERE mailjet_campaign_id IS NOT NULL OR mailjet_campaign_draft_id IS NOT NULL OR team_tip_name IS NOT NULL")
      assert_zero("SELECT COUNT(*) FROM newsletter_interests WHERE mailjet_segment_id IS NOT NULL")
      assert_zero("SELECT COUNT(*) FROM app_settings WHERE key IN (#{quoted_list(DISABLED_SETTINGS)}) AND value <> 'false'::jsonb")
      true
    end

    def create_admin!(password:)
      validate_target!
      raise Error, "Eigenes Staging-Passwort mit mindestens 32 Zeichen erforderlich" unless password.is_a?(String) && password.length.between?(32, 72)
      raise Error, "Vorhandene Admins zuerst bereinigen" unless @connection.select_value("SELECT COUNT(*) FROM users WHERE role = 'admin'").to_i.zero?
      digest = @connection.quote(BCrypt::Password.create(password).to_s)
      @connection.select_value(<<~SQL)
        INSERT INTO users (email_address, name, role, password_digest, created_at, updated_at)
        VALUES ('staging-admin@example.invalid', 'Staging Admin', 'admin', #{digest}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id
      SQL
    end

    private

    def validate_target!
      raise Error, "Sanitizer benötigt die eigene Staging-Datenbank" unless @connection.select_value("SELECT current_database()") == DATABASE
    end

    def remove_private_records
      @connection.delete("DELETE FROM active_storage_attachments WHERE record_type = 'EventSocialPost'")
      # Remove self-references before deleting every target (no token decryption).
      @connection.update("UPDATE social_connection_targets SET parent_target_id = NULL")
      EMPTY_TABLES.each { |table| @counts[table] = @connection.delete("DELETE FROM #{table}") }
    end

    def sanitize_users
      ids = @connection.select_values("SELECT id FROM users ORDER BY id")
      ids.each do |id|
        digest = @connection.quote(BCrypt::Password.create(SecureRandom.hex(32)).to_s)
        @connection.update(<<~SQL)
          UPDATE users SET email_address = 'user-' || id || '@example.invalid', name = 'Benutzer ' || id,
            password_digest = #{digest}, role = 'editor', failed_login_attempts = 0, last_failed_login_at = NULL, locked_until = NULL
          WHERE id = #{Integer(id)}
        SQL
      end
      @counts["users"] = ids.size
    end

    def sanitize_import_images
      @counts["removed_import_event_images"] = @connection.delete(<<~SQL)
        DELETE FROM import_event_images images
        WHERE images.import_class <> 'Event'
          OR NOT EXISTS (SELECT 1 FROM events WHERE events.id = images.import_event_id)
      SQL
      columns = @connection.columns("import_event_images").map(&:name)
      assignments = { "cache_status" => "'pending'", "cache_error" => "NULL", "cache_attempted_at" => "NULL", "cached_at" => "NULL" }.filter_map do |column, value|
        "#{column} = #{value}" if columns.include?(column)
      end
      update("import_event_images", assignments.join(", ")) if assignments.any?
    end

    def replace_import_history
      if @connection.select_value("SELECT COUNT(*) FROM event_llm_enrichments").to_i.positive?
        source = @connection.select_value("SELECT import_source_id FROM import_runs ORDER BY id LIMIT 1")
        raise Error, "Import-Fremdschlüssel unvollständig" unless source
        placeholder = @connection.select_value(<<~SQL)
          INSERT INTO import_runs (import_source_id, source_type, started_at, finished_at, status, created_at, updated_at)
          VALUES (#{Integer(source)}, 'staging_snapshot', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'completed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id
        SQL
        update("event_llm_enrichments", "source_run_id = #{Integer(placeholder)}")
        @counts["import_runs"] = @connection.delete("DELETE FROM import_runs WHERE id <> #{Integer(placeholder)}")
      else
        @counts["import_runs"] = @connection.delete("DELETE FROM import_runs")
      end
    end

    def sanitize_settings
      keep = PUBLIC_SETTINGS + DISABLED_SETTINGS
      @connection.delete("DELETE FROM app_settings WHERE key NOT IN (#{quoted_list(keep)})")
      DISABLED_SETTINGS.each do |key|
        @connection.execute(<<~SQL)
          INSERT INTO app_settings (key, value, created_at, updated_at) VALUES (#{@connection.quote(key)}, 'false'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          ON CONFLICT (key) DO UPDATE SET value = 'false'::jsonb
        SQL
      end
    end

    def sanitize_blob_metadata
      @connection.select_all("SELECT id, metadata FROM active_storage_blobs").each do |row|
        metadata = JSON.parse(row["metadata"].presence || "{}").slice("identified", "analyzed", "width", "height", "duration", "aspect_ratio")
        @connection.update("UPDATE active_storage_blobs SET service_name = 'local', filename = 'asset-' || id, metadata = #{@connection.quote(metadata.to_json)} WHERE id = #{Integer(row.fetch('id'))}")
      end
      @counts["active_storage_blobs"] = @connection.select_value("SELECT COUNT(*) FROM active_storage_blobs").to_i
    end

    def quoted_list(values)
      values.map { |value| @connection.quote(value) }.join(", ")
    end

    def update(table, assignments)
      @counts[table] = @connection.update("UPDATE #{table} SET #{assignments}")
    end

    def assert_zero(sql)
      raise Error, "Bereinigung unvollständig" unless @connection.select_value(sql).to_i.zero?
    end
  end
end
