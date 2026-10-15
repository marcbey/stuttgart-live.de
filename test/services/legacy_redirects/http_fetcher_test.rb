require "test_helper"

class LegacyRedirects::HttpFetcherTest < ActiveSupport::TestCase
  test "rejects unsafe URLs and all private resolved addresses before transport" do
    transport = ->(*) { flunk "unsafe transport" }
    fetcher = LegacyRedirects::HttpFetcher.new(transport: transport, dns: ->(_) { [ "127.0.0.1" ] }, interval: 0)
    %w[http://stuttgart-live.de/a https://evil.example/a https://stuttgart-live.de:444/a https://user:pass@stuttgart-live.de/a].each do |url|
      assert_raises(LegacyRedirects::HttpFetcher::Error) { fetcher.call(url) }
    end
  end

  test "revalidates every redirect and limits body size" do
    calls = []
    transport = lambda do |uri, **|
      calls << uri.to_s
      { status: 302, headers: { "location" => "http://127.0.0.1/private" }, body: "" }
    end
    fetcher = fetcher(transport)
    assert_raises(LegacyRedirects::HttpFetcher::Error) { fetcher.call("https://stuttgart-live.de/a") }
    assert_equal 1, calls.length
    fetcher = fetcher(->(*) { { status: 200, headers: {}, body: "a" * 11 } })
    assert_raises(LegacyRedirects::HttpFetcher::Error) { fetcher.call("https://stuttgart-live.de/a", max_bytes: 10) }
  end

  test "retries transient failures and returns explicit HTTP errors" do
    attempts = 0
    transport = lambda do |*, **|
      attempts += 1
      raise Timeout::Error if attempts == 1
      { status: 200, headers: { "content-type" => "text/html" }, body: "ok" }
    end
    assert_equal "ok", fetcher(transport).call("https://stuttgart-live.de/a").body
    assert_equal 2, attempts
    assert_raises(LegacyRedirects::HttpFetcher::Error) do
      fetcher(->(*) { { status: 503, headers: {}, body: "unavailable" } }).call("https://stuttgart-live.de/a")
    end
  end

  test "rejects mixed private DNS answers and mapped IPv6 loopback" do
    [ [ "93.184.216.34", "10.0.0.1" ], [ "::ffff:127.0.0.1" ], [ "169.254.169.254" ], [ "::1" ] ].each do |addresses|
      fetcher = LegacyRedirects::HttpFetcher.new(transport: ->(*) { flunk "unsafe transport" }, dns: ->(_) { addresses }, interval: 0)
      assert_raises(LegacyRedirects::HttpFetcher::Error) { fetcher.call("https://stuttgart-live.de/a") }
    end
  end

  test "bounds same-host redirect loops" do
    fetcher = fetcher(->(*) { { status: 302, headers: { "location" => "/loop" }, body: "" } })
    assert_match "Too many redirects", assert_raises(LegacyRedirects::HttpFetcher::Error) { fetcher.call("https://stuttgart-live.de/loop") }.message
  end

  test "applies robots URL guard to redirect destinations before requesting them" do
    fetcher = fetcher(->(*) { { status: 302, headers: { "location" => "/private/hidden" }, body: "" } })
    error = assert_raises(LegacyRedirects::HttpFetcher::Error) do
      fetcher.call("https://stuttgart-live.de/a", allowed: ->(url) { !URI(url).path.start_with?("/private/") })
    end
    assert_match "robots", error.message
  end

  private

  def fetcher(transport)
    LegacyRedirects::HttpFetcher.new(transport: transport, dns: ->(_) { [ "93.184.216.34" ] }, interval: 0)
  end
end
