require "test_helper"

class LegacyRedirects::InventoryTest < ActiveSupport::TestCase
  ROOT = "https://stuttgart-live.de"

  test "discovers namespaced sitemap pages and media and resumes successful rows" do
    responses = fixtures
    calls = []
    inventory(responses, calls).call
    assert_equal "event", LegacyRedirect.find_by!(source_path: "/events/christine").source_kind
    assert_equal "file", LegacyRedirect.find_by!(source_path: "/wp-content/uploads/foto.jpg").source_kind
    assert LegacyRedirect.find_by!(source_path: "/wp-content/uploads/foto.jpg").source_metadata["checksum"]
    refute LegacyRedirect.exists?(source_path: "/private/hidden")
    first_count = LegacyRedirect.count
    calls.clear
    inventory(responses, calls).call
    assert_equal first_count, LegacyRedirect.count
    refute_includes calls, "#{ROOT}/events/christine"
  end

  test "refresh preserves manual decisions and unchanged automatic resolution timestamps" do
    responses = fixtures
    inventory(responses).call
    row = LegacyRedirect.find_by!(source_path: "/events/christine")
    row.update!(checked_at: Time.current)
    checked_at = row.reload.checked_at
    inventory(responses, refresh: true).call
    assert_equal checked_at, row.reload.checked_at
    row.update!(origin: "manual", status: "disabled")
    responses["#{ROOT}/events/christine"] = "<main><h1>Changed</h1></main>"
    inventory(responses, refresh: true).call
    assert_equal "disabled", row.reload.status
    assert_equal "manual", row.origin
    assert_equal checked_at, row.checked_at
  end

  test "crawl errors remain retryable and successful retry clears them" do
    responses = fixtures
    responses["#{ROOT}/events/christine"] = LegacyRedirects::HttpFetcher::Error.new("HTTP 503")
    inventory(responses).call
    row = LegacyRedirect.find_by!(source_path: "/events/christine")
    assert_equal "HTTP 503", row.source_metadata["crawl_error"]
    assert_nil row.source_metadata["crawled_at"]
    responses["#{ROOT}/events/christine"] = "<main><h1>Recovered</h1></main>"
    inventory(responses).call
    assert_nil row.reload.source_metadata["crawl_error"]
    assert row.source_metadata["crawled_at"]
  end

  test "discovered event kind upgrades an earlier automatic page miss" do
    row = LegacyRedirect.create!(source_path: "/events/christine", source_kind: "page", checked_at: Time.current)
    inventory(fixtures).call
    assert_equal "event", row.reload.source_kind
    assert_nil row.checked_at
  end

  test "changed metadata invalidates automatic checked state" do
    responses = fixtures
    inventory(responses).call
    row = LegacyRedirect.find_by!(source_path: "/events/christine")
    row.update!(checked_at: Time.current)
    responses["#{ROOT}/events/christine"] = "<main><h1>New artist</h1></main>"
    inventory(responses, refresh: true).call
    assert_nil row.reload.checked_at
    assert_nil row.source_metadata["date"]
  end

  test "local blog seeding skips ambiguous source URLs and preserves manual blocks" do
    first = blog("First", "https://stuttgart-live.de/ambiguous/")
    blog("Second", "http://www.stuttgart-live.de/ambiguous")
    blocked = LegacyRedirect.create!(source_path: "/blocked-blog", source_kind: "news", origin: "manual", status: "disabled")
    blog("Blocked", "https://stuttgart-live.de/blocked-blog/")
    unique = blog("Unique", "https://stuttgart-live.de/unique-blog/")
    LegacyRedirects::Inventory.new.seed_blog_posts
    ambiguous = LegacyRedirect.find_by(source_path: "/ambiguous")
    refute ambiguous&.redirect?, "Duplicate normalized sources must not select one post"
    assert_equal "disabled", blocked.reload.status
    assert_equal unique, LegacyRedirect.find_by!(source_path: "/unique-blog").target
    assert first.persisted?
  end

  test "robots allow precedence and wildcard exclusions prevent trap crawling" do
    responses = fixtures
    responses["#{ROOT}/robots.txt"] = "User-agent: *\nDisallow: /events/*\nAllow: /events/christine$\n"
    inventory(responses).call
    assert LegacyRedirect.find_by!(source_path: "/events/christine").source_metadata["crawled_at"]
  end

  test "a manual block written during HTTP fetch wins over the inventory snapshot" do
    row = LegacyRedirect.create!(source_path: "/events/christine", source_kind: "event", checked_at: Time.current)
    responses = fixtures
    transport = Object.new
    transport.define_singleton_method(:call) do |url, **|
      LegacyRedirect.find(row.id).update!(origin: "manual", status: "disabled") if url.end_with?("/events/christine")
      LegacyRedirects::HttpFetcher::Response.new(url: url, status: 200, content_type: url.end_with?(".jpg") ? "image/jpeg" : "text/html", body: responses.fetch(url))
    end
    LegacyRedirects::Inventory.new(fetcher: transport).call
    assert_equal "manual", row.reload.origin
    assert_equal "disabled", row.status
    assert row.checked_at
  end

  test "robots groups with empty disallow do not inherit another bot restrictions" do
    responses = fixtures
    responses["#{ROOT}/robots.txt"] = "User-agent: *\nDisallow:\n\nUser-agent: OtherBot\nDisallow: /\n"
    inventory(responses).call
    assert LegacyRedirect.find_by!(source_path: "/events/christine").source_metadata["crawled_at"]
  end

  test "refresh updates evidence for a manual redirect whose event is no longer public" do
    event = events(:published_one)
    row = LegacyRedirect.create!(source_path: "/events/christine", source_kind: "event", origin: "manual", status: "redirect", target: event, checked_at: Time.current)
    row.update_columns(updated_at: 2.days.ago)
    decision = row.attributes.slice("origin", "status", "target_type", "target_id", "target_path", "checked_at")
    previous_updated_at = row.updated_at
    event.update!(status: "needs_review", published_at: nil)

    inventory(fixtures, refresh: true).call

    assert_equal decision, row.reload.attributes.slice(*decision.keys)
    assert_equal "Christine Thürmer", row.source_metadata["title"]
    assert row.source_metadata["crawled_at"]
    assert_operator row.updated_at, :>, previous_updated_at
    assert_nil LegacyRedirects::Target.path_for(row)
  end

  test "refresh records HTTP errors for a manual redirect whose event is no longer public" do
    event = events(:published_one)
    row = LegacyRedirect.create!(source_path: "/events/christine", source_kind: "event", origin: "manual", status: "redirect", target: event, checked_at: Time.current, source_metadata: { crawled_at: 1.day.ago.iso8601 })
    row.update_columns(updated_at: 2.days.ago)
    decision = row.attributes.slice("origin", "status", "target_type", "target_id", "target_path", "checked_at")
    previous_updated_at = row.updated_at
    event.update!(status: "needs_review", published_at: nil)
    responses = fixtures
    responses["#{ROOT}/events/christine"] = LegacyRedirects::HttpFetcher::Error.new("HTTP 503")

    inventory(responses, refresh: true).call

    assert_equal decision, row.reload.attributes.slice(*decision.keys)
    assert_equal "HTTP 503", row.source_metadata["crawl_error"]
    assert_nil row.source_metadata["crawled_at"]
    assert_operator row.updated_at, :>, previous_updated_at
  end

  test "automatic source kind upgrades and metadata refresh survive an unpublished target" do
    event = events(:published_one)
    row = LegacyRedirect.create!(source_path: "/events/christine", source_kind: "page", status: "redirect", target: event, checked_at: Time.current)
    decision = row.attributes.slice("origin", "status", "target_type", "target_id", "target_path")
    event.update!(status: "needs_review", published_at: nil)

    inventory(fixtures, refresh: true).call

    assert_equal decision, row.reload.attributes.slice(*decision.keys)
    assert_equal "event", row.source_kind
    assert_equal "Christine Thürmer", row.source_metadata["title"]
    assert_nil row.checked_at
  end

  def blog(title, source_url)
    BlogPost.create!(title: title, teaser: "Teaser", body: "<p>Article body</p>", author: users(:one), status: "published", published_at: 1.day.ago, source_url: source_url)
  end

  private

  def inventory(responses, calls = [], refresh: false)
    fetcher = Object.new
    fetcher.define_singleton_method(:call) do |url, **|
      calls << url
      value = responses.fetch(url) { raise LegacyRedirects::HttpFetcher::Error, "Missing fixture #{url}" }
      raise value if value.is_a?(Exception)
      type = url.end_with?(".jpg") ? "image/jpeg" : "text/html"
      LegacyRedirects::HttpFetcher::Response.new(url: url, status: 200, content_type: type, body: value)
    end
    LegacyRedirects::Inventory.new(fetcher: fetcher, refresh: refresh, max_pages: 20)
  end

  def fixtures
    {
      "#{ROOT}/robots.txt" => "User-agent: *\nDisallow: /private/\n",
      "#{ROOT}/sitemap_index.xml" => '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><sitemap><loc>https://stuttgart-live.de/event-sitemap.xml</loc></sitemap></sitemapindex>',
      "#{ROOT}/event-sitemap.xml" => '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1"><url><loc>https://stuttgart-live.de/events/christine</loc><image:image><image:loc>https://stuttgart-live.de/wp-content/uploads/foto.jpg</image:loc></image:image></url><url><loc>https://stuttgart-live.de/private/hidden</loc></url></urlset>',
      "#{ROOT}/events/christine" => '<main><h1>Christine Thürmer</h1><h2>10. November 2026</h2><a href="/wp-admin/">Admin</a></main>',
      "#{ROOT}/wp-content/uploads/foto.jpg" => "image bytes"
    }
  end
end
