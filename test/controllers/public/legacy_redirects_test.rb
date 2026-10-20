require "test_helper"

class Public::LegacyRedirectsTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:published_one)
  end

  test "controller not found is replaced by a cached permanent redirect" do
    rule = LegacyRedirect.create!(source_path: "/events/old-event", status: "redirect", origin: "manual", target: @event)
    get "#{rule.source_path}?utm_source=old"
    assert_response :moved_permanently
    assert_redirected_to event_path(@event.slug)
    assert_equal "public, max-age=300", response.headers["Cache-Control"]
    head rule.source_path
    assert_response :moved_permanently
    assert_empty response.body
  end

  test "an existing page wins over a matching redirect rule" do
    LegacyRedirect.create!(source_path: event_path(@event.slug), status: "redirect", origin: "manual", target_path: "/news")
    get event_path(@event.slug)
    assert_response :success
    assert_nil response.headers["Location"]
  end

  test "WordPress shortlink queries do not redirect a successful homepage" do
    get "/?p=429061"
    assert_response :success
    assert_nil response.headers["Location"]
  end

  test "missing file URLs redirect to a direct public file response" do
    post = BlogPost.create!(title: "Öffentliche Datei", teaser: "Öffentliche Datei Teaser", body: "<p>Inhalt</p>",
      author: users(:one), published_by: users(:one), status: "published", published_at: 1.day.ago)
    post.cover_image.attach(io: StringIO.new("public file bytes"), filename: "cover.txt", content_type: "image/png")
    rule = LegacyRedirect.create!(source_path: "/wp-content/uploads/2020/cover.png", source_kind: "file", status: "redirect", origin: "manual", target: post.cover_image.blob)
    get rule.source_path
    assert_response :moved_permanently
    assert_equal rule.destination, response.headers["Location"]
    follow_redirect!
    assert_response :success
    assert_equal "public file bytes", response.body
  end

  test "missing paths retain the existing error response" do
    get "/definitely-still-missing"
    assert_response :not_found
    assert_select "h1", "Ups! Diese Seite gibt es leider nicht."
  end

  test "inventoried WordPress event resolves automatically through its ticket provider" do
    @event.update!(artist_name: "Luvre47", title: "Motorsport Tour 2026", venue: "h14", city: "Stuttgart",
      start_at: Time.zone.local(2026, 10, 23, 20), slug: "luvre47-2026-10-23")
    @event.event_offers.create!(source: "eventim", source_event_id: "21515509", priority_rank: 0)
    source = "/events/luvre47"
    get "#{source}/"
    assert_response :not_found

    root = "https://stuttgart-live.de"
    responses = {
      "#{root}/robots.txt" => "User-agent: *\nDisallow:\n",
      "#{root}/sitemap_index.xml" => %(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><sitemap><loc>#{root}/event-sitemap.xml</loc></sitemap></sitemapindex>),
      "#{root}/event-sitemap.xml" => %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>#{root}#{source}/</loc></url></urlset>),
      "#{root}#{source}" => file_fixture("legacy_redirects/luvre47.html").read
    }
    fetcher = Object.new
    fetcher.define_singleton_method(:call) do |url, **|
      body = responses.fetch(url) { raise LegacyRedirects::HttpFetcher::Error, "HTTP 404" }
      LegacyRedirects::HttpFetcher::Response.new(url: url, status: 200, content_type: "text/html", body: body)
    end
    LegacyRedirects::Inventory.new(fetcher: fetcher).call

    get "#{source}/"
    assert_response :moved_permanently
    assert_equal "/events/luvre47-2026-10-23", response.headers["Location"]
    rule = LegacyRedirect.find_by!(source_path: source)
    assert_equal "event", rule.source_kind
    assert_equal "automatic", rule.origin
    assert_equal "provider_id", rule.match_reason
    assert_equal @event, rule.target
    assert_equal "2026-10-23T20:00:00+02:00", rule.source_metadata["start_at"]

    head "#{source}/?utm_source=regression"
    assert_response :moved_permanently
    assert_equal "/events/luvre47-2026-10-23", response.headers["Location"]
    assert_empty response.body
    follow_redirect!
    assert_response :success
  end
end
