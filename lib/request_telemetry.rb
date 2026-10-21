require "json"
require "logger"
require "securerandom"

# Timings stop when the Rack app returns; streaming body delivery is measured by nginx.
class RequestTelemetry
  def initialize(app, logger: nil, release: ENV["SENTRY_RELEASE"], wall_clock: -> { Time.now.to_f },
    monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @app = app
    @logger = logger || Logger.new($stdout, formatter: ->(_severity, _time, _progname, message) { "#{message}\n" })
    @release = (release.to_s.bytesize <= 64 && release.to_s.ascii_only? && release.to_s.match?(/\A[0-9a-f]{6,64}\z/)) ? release : "unknown"
    @wall_clock = wall_clock
    @monotonic_clock = monotonic_clock
  end

  def call(env)
    started = @monotonic_clock.call
    at = @wall_clock.call
    queue_ms = queue_time(env["HTTP_X_REQUEST_START"], at)
    request_id = env["HTTP_X_REQUEST_ID"].to_s
    request_id = SecureRandom.hex(16) unless request_id.bytesize == 32 && request_id.ascii_only? && request_id.match?(/\A[0-9a-f]{32}\z/)
    response = @app.call(env)
  ensure
    @logger.info(JSON.generate(event: "request_timing", at:, request_id:, release: @release,
      route: route(env["PATH_INFO"]), status: response ? response.first.to_i : 500, queue_ms:,
      app_ms: ((@monotonic_clock.call - started) * 1000).round(3), pools: self.class.pool_stats))
  end

  def self.pool_stats
    ActiveRecord::Base.connection_handler.connection_pool_list(:all).map do |pool|
      pool.stat.slice(:size, :busy, :dead, :idle, :waiting)
    end
  end

  private

  def queue_time(value, now)
    return unless value.is_a?(String) && value.bytesize <= 24 && value.ascii_only? && value.match?(/\A\d{10}\.\d{3}\z/)

    elapsed = now - value.to_f
    (elapsed * 1000).round(3) if elapsed.between?(0, 300)
  end

  def route(path)
    return "other" unless path.is_a?(String) && path.valid_encoding?

    case path
    when "/", "/up", "/search", "/events/search_overlay" then path
    when %r{\A/events/} then "/events/:id"
    when %r{\A/passwords(?:/|\z)} then "/passwords/*"
    when %r{\A/backend(?:/|\z)} then "/backend/*"
    when %r{\A/media/} then "/media/*"
    when %r{\A/assets/} then "/assets/*"
    else "other"
    end
  end
end
