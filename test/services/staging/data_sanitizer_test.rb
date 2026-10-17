require "test_helper"
require_relative "../../support/staging_database_fixture"

class StagingDataSanitizerTest < ActiveSupport::TestCase
  include StagingDatabaseFixture
  self.use_transactional_tests = false

  setup do
    open_staging_fixture(database: "stuttgart_live_de_staging", schema: Rails.root.join("db/schema.rb"))
  end

  teardown { close_staging_fixture }

  test "real foreign keys and public identities survive while private data disappears twice" do
    user = insert_stage("users", email_address: "real@customer.de", name: "Real Name", role: "admin", password_digest: "old-secret-digest")
    venue = insert_stage("venues", name: "Public Venue")
    event = insert_stage("events", title: "Concert", artist_name: "Artist", normalized_artist_name: "artist", slug: "concert", venue_id: venue, start_at: Time.current,
      status: "published", publish_on_russ_live: true, published_by_id: user, editor_notes: "private", source_snapshot: { secret: "private" })
    blog = insert_stage("blog_posts", author_id: user, author_name: "Real Author", title: "News", slug: "news", teaser: "Public", status: "published")
    source = insert_stage("import_sources", name: "Source", source_type: "reservix", settings: { secret: "token" })
    insert_stage("import_source_configs", import_source_id: source, settings: { key: "private" })
    run = insert_stage("import_runs", import_source_id: source, source_type: "reservix", started_at: Time.current, status: "failed", metadata: { private: true })
    enrichment = insert_stage("event_llm_enrichments", event_id: event, source_run_id: run, model: "model", prompt_version: "v1", event_description: "Public description", raw_response: { private: true })
    insert_stage("import_run_errors", import_run_id: run, source_type: "reservix", message: "private error")
    insert_stage("raw_event_imports", import_source_id: source, import_event_type: "Event", source_identifier: "1", payload: { secret: true })
    insert_stage("sessions", user_id: user, ip_address: "10.0.0.2", user_agent: "private")
    insert_stage("login_attempts", user_id: user, outcome: "failed", email_address: "real@customer.de")
    subscriber = insert_stage("newsletter_subscribers", email: "subscriber@customer.de", confirmation_nonce: "token")
    insert_stage("newsletter_consent_events", newsletter_subscriber_id: subscriber, email: "subscriber@customer.de", action: "subscribe", consent_version: "v1", occurred_at: Time.current, source: "public")
    genre = insert_stage("genres", name: "Rock", slug: "rock")
    interest = insert_stage("newsletter_interests", genre_id: genre, name: "Rock", slug: "rock", mailjet_property_name: "rock", mailjet_segment_id: 123)
    insert_stage("newsletter_subscriber_interests", newsletter_subscriber_id: subscriber, newsletter_interest_id: interest)
    issue = insert_stage("newsletter_issues", title: "Private name", subject: "Private", mailjet_campaign_id: 123, team_tip_name: "Real Name", team_tip_text: "private")
    connection = insert_stage("social_connections", provider: "meta", platform: "facebook", auth_mode: "oauth", user_access_token: "encrypted-but-no-decryption-needed")
    target = insert_stage("social_connection_targets", social_connection_id: connection, target_type: "page", external_id: "page", access_token: "token")
    insert_stage("social_connection_targets", social_connection_id: connection, target_type: "account", external_id: "child", parent_target_id: target, access_token: "token")
    post = insert_stage("event_social_posts", event_id: event, platform: "facebook")
    insert_stage("publish_attempts", event_social_post_id: post, social_connection_id: connection, social_connection_target_id: target, platform: "facebook", started_at: Time.current)
    image = insert_stage("event_images", event_id: event, purpose: "detail_hero")
    blob = insert_stage("active_storage_blobs", key: "abcdefghijklmnopqrstuvwx", filename: "private-person.jpg", service_name: "production_cloud", byte_size: 4, metadata: { private: "token", width: 10 }.to_json)
    attachment = insert_stage("active_storage_attachments", record_type: "EventImage", record_id: image, name: "file", blob_id: blob)
    insert_stage("app_settings", key: "daily_raw_import_enabled", value: true)

    2.times do
      result = Staging::DataSanitizer.call(connection: @stage)
      assert_kind_of Hash, result
      assert result.values.all? { |count| count.is_a?(Integer) }
      clean_user = stage_row("users", user)
      assert_equal "user-#{user}@example.invalid", clean_user["email_address"]
      assert_equal "editor", clean_user["role"]
      assert_not_equal "old-secret-digest", clean_user["password_digest"]
      assert BCrypt::Password.valid_hash?(clean_user["password_digest"])
      assert_equal "published", stage_row("events", event)["status"]
      assert_equal true, stage_row("events", event)["publish_on_russ_live"]
      assert_nil stage_row("events", event)["editor_notes"]
      assert_equal "{}", stage_row("events", event)["source_snapshot"]
      assert_equal user, stage_row("blog_posts", blog)["author_id"]
      assert_not_equal "Real Author", stage_row("blog_posts", blog)["author_name"]
      clean_enrichment = stage_row("event_llm_enrichments", enrichment)
      assert_equal "Public description", clean_enrichment["event_description"]
      assert_equal "{}", clean_enrichment["raw_response"]
      assert_not_equal run, clean_enrichment["source_run_id"]
      assert_equal 1, stage_count("import_runs")
      %w[sessions login_attempts newsletter_subscribers newsletter_subscriber_interests newsletter_consent_events social_connections social_connection_targets event_social_posts publish_attempts raw_event_imports import_run_errors].each do |table|
        assert_equal 0, stage_count(table), table
      end
      assert_equal false, stage_row("import_sources", source)["active"]
      assert_nil stage_row("newsletter_interests", interest)["mailjet_segment_id"]
      assert_nil stage_row("newsletter_issues", issue)["mailjet_campaign_id"]
      assert_nil stage_row("newsletter_issues", issue)["team_tip_name"]
      assert_equal blob, stage_row("active_storage_attachments", attachment)["blob_id"]
      assert_not_includes stage_row("active_storage_blobs", blob).values.join, "private"
      assert_equal "local", stage_row("active_storage_blobs", blob)["service_name"]
      assert_equal "false", @stage.select_value("SELECT value FROM app_settings WHERE key = 'daily_raw_import_enabled'")
    end
  end

  test "only the new staging admin can authenticate and missing or escaping media fails verification" do
    user = insert_stage("users", email_address: "old@customer.de", role: "admin", password_digest: BCrypt::Password.create("old password").to_s)
    Staging::DataSanitizer.call(connection: @stage)
    sanitizer = Staging::DataSanitizer.new(connection: @stage)
    password = "test-only-#{'x' * 32}"
    admin_id = sanitizer.create_admin!(password:)
    assert_equal 1, @stage.select_value("SELECT COUNT(*) FROM users WHERE role = 'admin'").to_i
    assert BCrypt::Password.new(stage_row("users", admin_id)["password_digest"]) == password
    assert_not BCrypt::Password.new(stage_row("users", user)["password_digest"]) == "old password"
    assert sanitizer.verify!(admin_id:)
    assert_raises(Staging::DataSanitizer::Error) { sanitizer.create_admin!(password:) }
    blob = insert_stage("active_storage_blobs", key: "abcdefghijklmnopqrstuvwx", filename: "image", service_name: "local", byte_size: 4)
    venue = insert_stage("venues", name: "Media venue")
    insert_stage("active_storage_attachments", record_type: "Venue", record_id: venue, name: "logo", blob_id: blob)
    Dir.mktmpdir do |root|
      assert_raises(Staging::MediaVerifier::Error) { Staging::MediaVerifier.call(connection: @stage, root:) }
      FileUtils.mkdir_p(File.join(root, "ab", "cd"))
      path = File.join(root, "ab", "cd", "abcdefghijklmnopqrstuvwx")
      File.write(path, "test")
      assert Staging::MediaVerifier.call(connection: @stage, root:)
      File.unlink(path)
      File.symlink("/etc/hosts", path)
      assert_raises(Staging::MediaVerifier::Error) { Staging::MediaVerifier.call(connection: @stage, root:) }
    end
  end

  test "incomplete unattached uploads are ignored while variant references require the original file" do
    blob = insert_stage("active_storage_blobs", key: "abcdefghijklmnopqrstuvwx", filename: "incomplete", service_name: "local", byte_size: 4)
    Dir.mktmpdir do |root|
      assert Staging::MediaVerifier.call(connection: @stage, root:)
      insert_stage("active_storage_variant_records", blob_id: blob, variation_digest: "variant")
      assert_raises(Staging::MediaVerifier::Error) { Staging::MediaVerifier.call(connection: @stage, root:) }
      FileUtils.mkdir_p(File.join(root, "ab", "cd"))
      File.write(File.join(root, "ab", "cd", "abcdefghijklmnopqrstuvwx"), "test")
      assert Staging::MediaVerifier.call(connection: @stage, root:)
    end
  end

  test "actual non-staging database is refused before mutation" do
    @stage.execute("CREATE DATABASE stuttgart_live_de_production")
    config = StagingFixtureRecord.connection_db_config.configuration_hash.merge(database: "stuttgart_live_de_production")
    StagingFixtureRecord.establish_connection(config)
    wrong = StagingFixtureRecord.connection
    wrong.execute("CREATE TABLE sentinel (value text)")
    wrong.execute("INSERT INTO sentinel VALUES ('unchanged')")
    assert_raises(Staging::DataSanitizer::Error) { Staging::DataSanitizer.call(connection: wrong) }
    assert_equal "unchanged", wrong.select_value("SELECT value FROM sentinel")
  end
end
