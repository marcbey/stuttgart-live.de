require "bundler/setup"
require "minitest/autorun"
require "active_support"
require "active_support/encrypted_file"
require "yaml"
require "json"
require "tmpdir"
require "securerandom"
require_relative "../../script/ops/compatibility_probe"

class CompatibilityRuntimeCheck < Minitest::Test
  class ExportVerifyingProbe < Ops::CompatibilityProbe
    attr_reader :exported_projects

    private

    def probe_app(project)
      super
      program = "PROJECT = #{project.inspect}\nEXPORT_MODE = 'data'\n" + File.read(File.expand_path("../../script/ops/compatibility_export.rb", __dir__))
      output = inner("exec", "--interactive", project, "bundle", "exec", "ruby", "-", input: program)
      rows = output.lines.map { |line| JSON.parse(line) }
      header = rows.shift
      raise "Exportkopf passt nicht zur Staging-App" unless header["kind"] == "header" && header["project"] == project && header["database"] == "#{project}_staging"
      if project == "stuttgart_live_de"
        users = rows.select { |row| row["table"] == "users" }.map { |row| row.fetch("record") }
        raise "Staging-Konten wurden nicht erneut maskiert" unless !users.empty? && users.all? { |user| user["email_address"] == "user-#{user.fetch('id')}@example.invalid" && user["role"] == "editor" }
      end
      (@exported_projects ||= []) << project
    end
  end

  def test_disconnected_real_images_share_authentication_on_an_isolated_schema_copy
    images = { "stuttgart_live_de" => ENV.fetch("S_IMAGE"), "russ_live_de" => ENV.fetch("R_IMAGE") }.transform_values do |tag|
      Ops::ReleaseSupport.capture("docker", "image", "inspect", "--format", "{{.Id}}", tag).strip
    end
    roots = { "stuttgart_live_de" => ENV.fetch("S_SOURCE_ROOT"), "russ_live_de" => ENV.fetch("R_SOURCE_ROOT") }
    Dir.mktmpdir("compatibility-runtime-") do |directory|
      apps = images.to_h do |project, reference|
        schema_path = project == "stuttgart_live_de" ? "db/schema.rb" : "db/russ_schema.rb"
        migration_path = project == "stuttgart_live_de" ? "db/migrate" : "db/russ_migrate"
        versions = Dir.glob(File.join(roots.fetch(project), migration_path, "*.rb")).map { |file| File.basename(file).split("_").first }.sort
        rows = project == "stuttgart_live_de" ? stuttgart_rows : {}
        header = { kind: "header", project:, database: "#{project}_staging", schema: File.read(File.join(roots.fetch(project), schema_path)), versions:,
          columns: rows.to_h { |table, records| [ table, records.flat_map(&:keys).uniq.map(&:to_s) ] } }
        data = File.join(directory, "#{project}.jsonl")
        File.open(data, "w", 0o600) do |file|
          file.puts JSON.generate(header)
          rows.each { |table, records| records.each { |record| file.puts JSON.generate(table:, record:) } }
        end
        key = ActiveSupport::EncryptedFile.generate_key
        encrypted = File.join(directory, "#{project}.enc")
        old_key, ENV["COMPATIBILITY_TEST_KEY"] = ENV["COMPATIBILITY_TEST_KEY"], key
        file = ActiveSupport::EncryptedFile.new(content_path: encrypted, key_path: File.join(directory, "unused.key"), env_key: "COMPATIBILITY_TEST_KEY", raise_if_missing_key: true)
        file.write({ secret_key_base: SecureRandom.hex(64), active_record_encryption: { primary_key: SecureRandom.hex(32), deterministic_key: SecureRandom.hex(32), key_derivation_salt: SecureRandom.hex(32) } }.to_yaml)
        ENV["COMPATIBILITY_TEST_KEY"] = old_key
        [ project, { "reference" => reference, "data_path" => data, "schema_path" => data, "credentials_path" => encrypted, "master_key" => key } ]
      end
      probe = ExportVerifyingProbe.new
      assert probe.run_sandbox(directory:, apps:)
      assert_equal images.keys.sort, probe.exported_projects.sort
    end
  end

  def stuttgart_rows
    now = Time.now.utc.iso8601
    timestamps = { created_at: now, updated_at: now }
    {
      "users" => [ timestamps.merge(id: 50, email_address: "user-50@example.invalid", name: "Benutzer 50", role: "editor", password_digest: BCrypt::Password.create(SecureRandom.hex(32), cost: BCrypt::Engine::MIN_COST).to_s) ],
      "venues" => [ timestamps.merge(id: 60, name: "Probe Venue") ],
      "events" => [ timestamps.merge(id: 80, venue_id: 60, title: "Probe Concert", artist_name: "Probe Artist", normalized_artist_name: "probe artist", slug: "probe-concert", start_at: (Time.now.utc + 86_400).iso8601, status: "published", publish_on_russ_live: true) ]
    }
  end
end
