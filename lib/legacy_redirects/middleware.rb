module LegacyRedirects
  class Middleware
    EXCLUDED_PREFIXES = %w[backend rails session passwords login media assets up 400 404 422 500 errors recede_historical_location resume_historical_location refresh_historical_location].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      path = env["PATH_INFO"].to_s.dup
      query = env["QUERY_STRING"].to_s.dup
      response = @app.call(env)
      return response unless response[0].to_i == 404 && %w[GET HEAD].include?(env["REQUEST_METHOD"])
      return response if EXCLUDED_PREFIXES.include?(path.split("/", 3)[1].to_s.split(".", 2).first)

      redirect_response(path, query, response)
    end

    private

    def redirect_response(path, query, response)
      result = ::LegacyRedirects::Resolver.call(path: path, query: query)
      return response unless result.status.to_s == "redirect" && !result.destination.to_s.empty?

      response[2].close if response[2].respond_to?(:close)
      [ 301, { "location" => result.destination, "cache-control" => "public, max-age=300", "content-type" => "text/html; charset=utf-8" }, [] ]
    rescue StandardError => error
      report_error(error)
      response
    end

    def report_error(error)
      Rails.logger.warn("Legacy redirect resolution failed: #{error.class}: #{error.message}")
      Sentry.capture_exception(error) if defined?(Sentry)
    rescue StandardError
      nil
    end
  end
end
