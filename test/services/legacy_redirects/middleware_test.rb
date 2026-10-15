require "test_helper"
require Rails.root.join("lib/legacy_redirects/middleware")

class LegacyRedirectMiddlewareTest < ActiveSupport::TestCase
  Result = Data.define(:status, :destination)
  ClosingBody = Struct.new(:closed) do
    def each
      yield "Not found"
    end

    def close
      self.closed = true
    end
  end

  test "replaces only actual GET and HEAD 404 responses and closes replaced body" do
    body = ClosingBody.new(false)
    app = ->(env) { env["PATH_INFO"] = "/404"; [ 404, { "x-original" => "yes" }, body ] }
    middleware = LegacyRedirects::Middleware.new(app)
    test_case = self
    resolver = ->(path:, query:) do
      test_case.assert_equal "/old.pdf", path
      test_case.assert_equal "utm_source=x", query
      Result.new(:redirect, "/news")
    end
    with_resolver(resolver) do
      %w[GET HEAD].each do |method|
        status, headers, response_body = middleware.call("REQUEST_METHOD" => method, "PATH_INFO" => "/old.pdf", "QUERY_STRING" => "utm_source=x", "HTTP_ACCEPT" => "application/pdf")
        assert_equal 301, status
        assert_equal "/news", headers["location"]
        assert_equal "public, max-age=300", headers["cache-control"]
        assert_empty response_body
        assert body.closed
      end
    end
  end

  test "preserves successful error and non-idempotent responses without resolver" do
    test_case = self
    resolver = ->(**) { test_case.flunk "resolver must not run" }
    with_resolver(resolver) do
      [ [ "GET", "/old", 200 ], [ "GET", "/old", 403 ], [ "GET", "/old", 500 ], [ "POST", "/old", 404 ], [ "GET", "/backend/a", 404 ], [ "GET", "/media/a", 404 ], [ "GET", "/rails/active_storage/a", 404 ], [ "GET", "/404", 404 ], [ "GET", "/404.json", 404 ], [ "GET", "/backend.json", 404 ] ].each do |method, path, status|
        original = [ status, { "x-original" => "yes" }, [ "Original" ] ]
        assert_same original, LegacyRedirects::Middleware.new(->(_) { original }).call("REQUEST_METHOD" => method, "PATH_INFO" => path)
      end
    end
  end

  test "resolver failures and disabled or unresolved rules preserve original response" do
    original = [ 404, {}, [ "Original" ] ]
    middleware = LegacyRedirects::Middleware.new(->(_) { original })
    [ ->(**) { raise "resolver unavailable" }, ->(**) { Result.new(:disabled, nil) }, ->(**) { Result.new(:not_found, nil) } ].each do |resolver|
      with_resolver(resolver) do
        assert_same original, middleware.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/old")
      end
    end
  end

  test "reporting failures cannot replace original missing response" do
    original = [ 404, {}, [ "Original" ] ]
    middleware = LegacyRedirects::Middleware.new(->(_) { original })
    logger = Rails.logger
    broken_logger = Object.new
    broken_logger.define_singleton_method(:warn) { |*| raise "logger unavailable" }
    Rails.logger = broken_logger
    with_resolver(->(**) { raise "resolver unavailable" }) do
      assert_same original, middleware.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/old")
    end
  ensure
    Rails.logger = logger
  end

  test "does not rescue exceptions from the underlying application" do
    middleware = LegacyRedirects::Middleware.new(->(_) { raise ArgumentError, "application failed" })
    assert_raises(ArgumentError) { middleware.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/old") }
  end

  private

  def with_resolver(callable)
    original = LegacyRedirects.const_get(:Resolver) if LegacyRedirects.const_defined?(:Resolver)
    LegacyRedirects.send(:remove_const, :Resolver) if original
    replacement = Class.new
    replacement.define_singleton_method(:call, &callable)
    LegacyRedirects.const_set(:Resolver, replacement)
    yield
  ensure
    LegacyRedirects.send(:remove_const, :Resolver)
    LegacyRedirects.const_set(:Resolver, original) if original
  end
end
