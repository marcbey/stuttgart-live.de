require "test_helper"

class Public::SitemapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    StaticPageDefaults.ensure!
    @author = users(:one)
  end

  test "show renders a dynamic sitemap with public future content" do
    future_event = create_event(
      slug: "sitemap-future-event",
      title: "Sitemap Future Event",
      artist_name: "Sitemap Artist",
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0)
    )
    past_event = create_event(
      slug: "sitemap-past-event",
      title: "Sitemap Past Event",
      artist_name: "Sitemap Past Artist",
      start_at: 2.days.ago.change(hour: 20, min: 0, sec: 0)
    )
    draft_event = create_event(
      slug: "sitemap-draft-event",
      title: "Sitemap Draft Event",
      artist_name: "Sitemap Draft Artist",
      start_at: 14.days.from_now.change(hour: 20, min: 0, sec: 0),
      status: "needs_review",
      published_at: nil
    )
    scheduled_event = create_event(
      slug: "sitemap-scheduled-event",
      title: "Sitemap Scheduled Event",
      artist_name: "Sitemap Scheduled Artist",
      start_at: 16.days.from_now.change(hour: 20, min: 0, sec: 0),
      published_at: 2.days.from_now
    )
    live_post = create_blog_post(title: "Sitemap Live News", status: "published", published_at: 1.hour.ago)
    draft_post = create_blog_post(title: "Sitemap Draft News", status: "draft")
    scheduled_post = create_blog_post(title: "Sitemap Scheduled News", status: "published", published_at: 1.day.from_now)

    get sitemap_url(format: :xml)

    assert_response :success
    assert_equal "application/xml", response.media_type

    document = Nokogiri::XML(response.body)
    assert_empty document.errors
    document.remove_namespaces!
    locs = document.css("url loc").map(&:text)

    assert_includes locs, root_url
    assert_includes locs, highlights_lane_url
    assert_includes locs, contact_url
    assert_includes locs, event_url(future_event.slug)
    assert_includes locs, news_url(live_post.slug)
    assert_not_includes locs, event_url(past_event.slug)
    assert_not_includes locs, event_url(draft_event.slug)
    assert_not_includes locs, event_url(scheduled_event.slug)
    assert_not_includes locs, news_url(draft_post.slug)
    assert_not_includes locs, news_url(scheduled_post.slug)
  end

  private
    def create_event(slug:, title:, artist_name:, start_at:, status: "published", published_at: 1.day.ago)
      Event.create!(
        slug: slug,
        source_fingerprint: "test::sitemap::#{slug}",
        title: title,
        artist_name: artist_name,
        start_at: start_at,
        venue: "Im Wizemann",
        city: "Stuttgart",
        status: status,
        published_at: published_at,
        source_snapshot: {}
      )
    end

    def create_blog_post(title:, status:, published_at: nil)
      BlogPost.create!(
        title: title,
        teaser: "#{title} teaser",
        body: "<div>#{title} body</div>",
        author: @author,
        status: status,
        published_at: published_at,
        published_by: (status == "published" ? @author : nil)
      )
    end
end
