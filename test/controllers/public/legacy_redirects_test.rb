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
    assert_select "h1", "Diese Seite gibt es nicht."
  end
end
