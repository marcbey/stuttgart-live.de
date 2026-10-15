require "test_helper"

class LegacyRedirects::PageExtractorTest < ActiveSupport::TestCase
  test "extracts event evidence and ignores footer providers" do
    html = file_fixture("legacy_redirects/event.html").read
    result = LegacyRedirects::PageExtractor.new(html, url: "https://stuttgart-live.de/events/christine/").call
    assert_equal "Christine Thürmer", result.metadata["artist_name"]
    assert_equal "WANDERN. WEITER. LEBEN.", result.metadata["production"]
    assert_equal "2026-11-10", result.metadata["date"]
    assert_equal false, result.metadata["time_known"]
    assert_nil result.metadata["start_at"]
    assert_equal "Theaterhaus, Stuttgart", result.metadata["venue"]
    assert_equal "429061", result.metadata["wordpress_id"]
    assert_equal [ { "source" => "easyticket", "id" => "103353" } ], result.metadata["provider_ids"]
    assert_equal "2026-02-01T10:00:00+01:00", result.metadata["published_at"]
    assert_includes result.links, "https://stuttgart-live.de/weitere-seite/"
    assert_includes result.media, "https://stuttgart-live.de/wp-content/uploads/foto.jpg"
  end

  test "does not invent missing year and extracts repeated dates with explicit times" do
    result = extract("<h1>Band</h1><h2>10. November</h2>")
    assert_nil result.metadata["date"]
    result = extract("<h1>Band</h1><h2>10. November 2026, 20:00 Uhr</h2><h2>11. November 2026, 19:30 Uhr</h2>")
    assert_equal 2, result.metadata["dates"].length
    assert_equal "2026-11-10T20:00:00+01:00", result.metadata["dates"].first["start_at"]
  end

  test "falls back to Yoast WebPage metadata without inventing a year" do
    result = extract('<script type="application/ld+json">{"@graph":[{"@type":"WebPage","name":"A festival","description":"A special festival on 10. November"}]}</script>')
    assert_equal "A festival", result.metadata["title"]
    assert_equal "A special festival on 10. November", result.metadata["content"]
    assert_nil result.metadata["date"]
  end

  test "recognizes printed German dates with separated time and numeric dates" do
    result = extract("<main><h1>Band</h1><h2>10. November 2026 – 20:00 Uhr</h2><h2>11.11.2026, 19:30 Uhr</h2></main>")
    assert_equal "2026-11-10T20:00:00+01:00", result.metadata["dates"].first["start_at"]
    assert_equal "2026-11-11T19:30:00+01:00", result.metadata["dates"].last["start_at"]
  end

  test "extracts real WordPress header production time and ticket evidence" do
    result = extract(file_fixture("legacy_redirects/christine_real.html").read)
    assert_equal "Wandern total - die Welt zu Deinen Füßen", result.metadata["production"]
    assert_equal "Christine Thürmer", result.metadata["artist_name"]
    assert_equal "2026-11-10", result.metadata["date"]
    assert_equal true, result.metadata["time_known"]
    assert_equal "2026-11-10T20:00:00+01:00", result.metadata["start_at"]
    assert_equal "Theaterhaus, Stuttgart", result.metadata["venue"]
    assert_equal [ { "source" => "easyticket", "id" => "103353" } ], result.metadata["provider_ids"]
    assert_equal "2025-05-28T10:00:28+00:00", result.metadata["published_at"]
    refute_includes result.metadata["content"], "Ähnliche Konzerte"
  end

  private

  def extract(html)
    LegacyRedirects::PageExtractor.new(html, url: "https://stuttgart-live.de/events/band/").call
  end
end
