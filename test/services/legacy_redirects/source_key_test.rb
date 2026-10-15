require "test_helper"

class LegacyRedirectSourceKeyTest < ActiveSupport::TestCase
  test "normalizes own absolute URLs, trailing slash and tracking keys" do
    assert_equal "/Alte-Seite", LegacyRedirects::SourceKey.normalize("https://www.stuttgart-live.de/Alte-Seite/?utm_source=x&gclid=1")
    assert_equal "/", LegacyRedirects::SourceKey.normalize("/")
    assert_equal "/caf%C3%A9", LegacyRedirects::SourceKey.normalize("/café/")
    assert_equal "/caf%C3%A9", LegacyRedirects::SourceKey.normalize("/caf%c3%a9")
    assert_equal "/abc", LegacyRedirects::SourceKey.normalize("/%61bc")
  end

  test "rejects unsafe and functional source identities" do
    [ "https://evil.test/a", "//evil.test/a", "/a?event=1", "/a?utm_source=x&p=1", "/a#part", "/a\\b", "/a/../b", "/a/%2e%2e/b", "/a%2fb", "/a%5cb", "/a%252fb", "/a%00b", "/a%ZZ", "/a\nb", "relative", "http://stuttgart-live.de:3000/a", "/%FF" ].each do |path|
      assert_nil LegacyRedirects::SourceKey.normalize(path), path.inspect
    end
  end

  test "rejects internal endpoints but preserves ordinary similar prefixes" do
    %w[/backend /backend/events /rails/x /session/new /passwords/new /login /media/a /assets/a /up /400 /404 /422 /500 /errors/404 /404.json /backend.json /rails/info /recede_historical_location].each do |path|
      assert_nil LegacyRedirects::SourceKey.normalize(path), path
    end
    assert_equal "/backend-story", LegacyRedirects::SourceKey.normalize("/backend-story")
  end
end
