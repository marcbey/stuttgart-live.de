require "test_helper"

class PublicImagesHttpFetcherTest < ActiveSupport::TestCase
  test "accepts public provider URLs while keeping legacy allowlist closed" do
    options = { dns: ->(_) { [ "93.184.216.34" ] }, transport: ->(*) { { status: 200, headers: {}, body: "ok" } }, interval: 0 }
    assert_equal "ok", PublicImages::HttpFetcher.new(**options).call("https://images.example/photo").body
    assert_raises(LegacyRedirects::HttpFetcher::Error) { LegacyRedirects::HttpFetcher.new(**options).call("https://images.example/photo") }
  end

  test "rejects unsafe URLs and rebinding redirect destinations" do
    calls = 0
    transport = ->(*) { calls += 1; { status: 302, headers: { "location" => "/next" }, body: "" } }
    resolver = ->(_) { calls.zero? ? [ "93.184.216.34" ] : [ "127.0.0.1" ] }
    fetcher = PublicImages::HttpFetcher.new(dns: resolver, transport:, interval: 0)
    %w[file:///etc/passwd https://user:secret@images.example/a https://images.example:444/a https://images.example/a#fragment].each do |url|
      assert_raises(PublicImages::HttpFetcher::Error) { fetcher.call(url) }
    end
    assert_raises(PublicImages::HttpFetcher::Error) { fetcher.call("https://images.example/photo") }
    assert_equal 1, calls
  end

  test "stream deadline includes transport and exception chains omit URL secrets" do
    fetcher = PublicImages::HttpFetcher.new(dns: ->(_) { [ "93.184.216.34" ] }, transport: ->(*) { sleep 0.1 }, total_timeout: 0.02, interval: 0)
    assert_raises(PublicImages::HttpFetcher::Error) { fetcher.call("https://images.example/photo") }
    fetcher = PublicImages::HttpFetcher.new(dns: ->(_) { raise SocketError, "https://images.example/?token=secret" }, interval: 0)
    error = assert_raises(PublicImages::HttpFetcher::Error) { fetcher.call("https://images.example/photo") }
    assert_no_match(/token|secret/, error.full_message)
  end

  test "total deadline bounds DNS and slow streams and errors omit source secrets" do
    fetcher = PublicImages::HttpFetcher.new(dns: ->(_) { sleep 0.1; [ "93.184.216.34" ] }, total_timeout: 0.02, interval: 0)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(PublicImages::HttpFetcher::Error) { fetcher.call("https://images.example/photo?token=secret") }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.1
    assert_no_match(/secret|token/, error.message)
  end
end
