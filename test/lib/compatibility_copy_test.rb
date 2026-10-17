require "test_helper"
require_relative "../support/staging_database_fixture"
require_relative "../../script/ops/compatibility_copy"

class CompatibilityCopyTest < ActiveSupport::TestCase
  include StagingDatabaseFixture
  self.use_transactional_tests = false
  setup { open_staging_fixture(database: "stuttgart_live_de_staging", schema: Rails.root.join("db/schema.rb")) }
  teardown { close_staging_fixture }

  test "copy refuses every database without an explicit isolated-server marker" do
    id = insert_stage("users", email_address: "sentinel@example.invalid", password_digest: "sentinel")
    assert_raises(Ops::CompatibilityCopy::Error) { Ops::CompatibilityCopy.call(connection: @stage, data_path: "/does-not-exist") }
    assert_equal "sentinel", stage_row("users", id)["password_digest"]
  end

  test "copy preserves IDs and constraints and tolerates extra source columns" do
    @stage.execute("SET live.compatibility_sandbox = 'on'")
    Dir.mktmpdir do |root|
      path = File.join(root, "data.jsonl")
      File.open(path, "w") do |file|
        file.puts({ "kind" => "header", "columns" => { "users" => %w[id email_address password_digest name role created_at updated_at future_column], "blog_posts" => %w[id author_id slug title teaser created_at updated_at] } }.to_json)
        file.puts({ "table" => "users", "record" => { id: 50, email_address: "user-50@example.invalid", password_digest: "fixture", role: "editor", name: "Benutzer 50", created_at: Time.current, updated_at: Time.current, future_column: "optional" } }.to_json)
        file.puts({ "table" => "blog_posts", "record" => { id: 70, author_id: 50, slug: "news", title: "Public news", teaser: "Public", created_at: Time.current, updated_at: Time.current } }.to_json)
      end
      result = Ops::CompatibilityCopy.call(connection: @stage, data_path: path)
      assert_equal 2, result.fetch("rows")
      assert_equal 50, stage_row("blog_posts", 70)["author_id"]
      assert_raises(ActiveRecord::InvalidForeignKey) { @stage.execute("DELETE FROM users WHERE id = 50") }
      assert_operator insert_stage("users", email_address: "next@example.invalid", password_digest: "fixture"), :>, 50
    end
  end
end
