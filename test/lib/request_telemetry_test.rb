require "test_helper"
require "stringio"

class RequestTelemetryTest < ActiveSupport::TestCase
  setup { assert defined?(RequestTelemetry), "request telemetry is not installed" }
  test "records queue and application milliseconds without request secrets" do
    entry, response = record({ "HTTP_X_REQUEST_START" => "1700000000.125", "HTTP_X_REQUEST_ID" => "a" * 32,
      "PATH_INFO" => "/passwords/secret-reset-token/edit", "QUERY_STRING" => "token=query-secret", "HTTP_COOKIE" => "cookie-secret" })
    assert_equal 204, response.first
    assert_equal 125.0, entry.fetch("queue_ms")
    assert_equal 25.0, entry.fetch("app_ms")
    assert_equal "/passwords/*", entry.fetch("route")
    assert_equal "a" * 32, entry.fetch("request_id")
    assert_equal "abc123", entry.fetch("release")
    refute_match(/secret|token|cookie/, entry.to_json)
  end

  test "missing malformed future stale and oversized starts are ignored" do
    [ nil, "", "t=1700000000.125", "NaN", "Infinity", "1700000001.000", "1699999000.000", "1" * 100_000, "1700000000.125\n", "0", "-1", "1700000000.12\xFF".b.force_encoding("UTF-8") ].each do |value|
      entry, = record({ "HTTP_X_REQUEST_START" => value })
      assert_nil entry.fetch("queue_ms"), value.inspect.truncate(80)
    end
  end

  test "unknown paths and spoofed identifiers cannot leak into structured logs" do
    entry, = record({ "PATH_INFO" => "/unknown/reset-secret", "HTTP_X_REQUEST_ID" => "external-secret" }, release: "secret\ninvalid")
    assert_equal "other", entry.fetch("route")
    assert_match(/\A[0-9a-f]{32}\z/, entry.fetch("request_id"))
    assert_equal "unknown", entry.fetch("release")
    refute_includes entry.to_json, "secret"
  end

  test "pool inspection uses existing counters without checkout or SQL" do
    queries = []
    before = ActiveRecord::Base.connection_pool.stat
    callback = ->(event) { queries << event.payload.fetch(:sql) }
    entries = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { RequestTelemetry.pool_stats }
    assert_empty queries
    assert_equal before, ActiveRecord::Base.connection_pool.stat
    assert entries.any? { |entry| entry[:size] == before[:size] }
    assert entries.all? { |entry| entry.keys.sort == %i[busy dead idle size waiting].sort }
  end

  test "application exceptions retain a sanitized timing entry and propagate" do
    output = StringIO.new
    middleware = RequestTelemetry.new(->(_env) { raise "private failure" }, logger: Logger.new(output))
    assert_raises(RuntimeError) { middleware.call("PATH_INFO" => "/bad/secret") }
    assert_includes output.string, '"status":500'
    refute_match(/private failure|secret/, output.string)
  end

  private

  def record(env, release: "abc123")
    output = StringIO.new
    logger = Logger.new(output, formatter: ->(_severity, _time, _progname, message) { "#{message}\n" })
    clock = [ 10.0, 10.025 ]
    middleware = RequestTelemetry.new(->(_env) { [ 204, {}, [] ] }, logger:, release:,
      wall_clock: -> { 1700000000.250 }, monotonic_clock: -> { clock.shift })
    response = middleware.call({ "PATH_INFO" => "/" }.merge(env))
    [ JSON.parse(output.string), response ]
  end
end
