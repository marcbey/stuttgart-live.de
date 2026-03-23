require "test_helper"

class Public::NewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    @live_post = create_blog_post(title: "Live News", status: "published", published_at: 2.hours.ago)
    @draft_post = create_blog_post(title: "Draft News", status: "draft")
    @scheduled_post = create_blog_post(title: "Scheduled News", status: "published", published_at: 2.hours.from_now)
  end

  test "index is publicly accessible and only shows live posts" do
    get news_index_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "News"
    assert_includes response.body, "Aktuelle News"
    assert_includes response.body, @live_post.title
    assert_not_includes response.body, @draft_post.title
    assert_not_includes response.body, @scheduled_post.title
  end

  test "index inserts newsletter signup only once after the first four live posts" do
    8.times do |index|
      create_blog_post(
        title: "Weitere News #{index}",
        status: "published",
        published_at: (index + 3).hours.ago
      )
    end

    get news_index_url

    assert_response :success
    assert_select ".news-index-newsletter-slot", count: 1
  end

  test "show renders a published post" do
    get news_url(@live_post.slug)

    assert_response :success
    assert_includes response.body, @live_post.title
    assert_includes response.body, @live_post.teaser
    assert_includes response.body, @live_post.display_author_name
    assert_includes response.body, "alle news"
    assert_select "h2", text: "Artikel"
  end

  test "show includes edit link for authenticated blog users" do
    sign_in_as(users(:blogger))

    get news_url(@live_post.slug)

    assert_response :success
    assert_select ".event-detail-topbar-actions .button.event-detail-edit-link[href='#{edit_backend_blog_post_path(@live_post)}']",
                  text: "Edit"
    assert_no_match(/Bearbeiten/, response.body)
  end

  test "index renders optimized cover images" do
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    get news_index_url

    assert_response :success
    assert_includes response.body, url_for(@live_post.processed_optimized_image_variant(:cover_image))
  end

  test "show renders optimized cover images" do
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    get news_url(@live_post.slug)

    assert_response :success
    assert_includes response.body, URI.parse(url_for(@live_post.processed_optimized_image_variant(:cover_image))).path
  end

  test "show renders hero image with shared event detail figure markup and without crop inline styles" do
    @live_post.update!(cover_image_focus_x: 20, cover_image_focus_y: 80, cover_image_zoom: 180)
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    get news_url(@live_post.slug)

    assert_response :success
    assert_select ".event-detail-image-wrap .event-detail-image-figure", count: 1
    assert_select ".event-detail-image-wrap .event-detail-image-frame", count: 0
    assert_select ".event-detail-image-wrap img.event-detail-image:not([style])", count: 1
    assert_no_match(/object-position:/, response.body)
    assert_no_match(/transform: scale/, response.body)
  end

  test "show renders seo tags and article schema" do
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    get news_url(@live_post.slug)

    assert_response :success
    assert_select "meta[name='description']", count: 1
    assert_select "meta[property='og:url'][content=?]", news_url(@live_post.slug)
    assert_select "meta[property='og:image']", count: 1
    assert_select "link[rel='canonical'][href=?]", news_url(@live_post.slug)
    assert_match(/"@type":"NewsArticle"/, response.body)
    assert_match(/"url":"#{Regexp.escape(news_url(@live_post.slug))}"/, response.body)
  end

  test "show renders image copyright" do
    @live_post.update!(cover_image_copyright: "Foto: Redaktion")
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    get news_url(@live_post.slug)

    assert_response :success
    assert_includes response.body, "Foto: Redaktion"
  end

  test "show returns not found for drafts" do
    get news_url(@draft_post.slug)

    assert_response :not_found
  end

  test "show gates youtube embeds behind consent placeholder" do
    post = create_blog_post(
      title: "Video News",
      status: "published",
      published_at: 1.hour.ago,
      youtube_video_urls: [ "https://youtu.be/dQw4w9WgXcQ" ]
    )

    get news_url(post.slug)

    assert_response :success
    assert_includes response.body, "YouTube laden"
    assert_select "[data-consent-media-target='frame'] iframe", count: 0
    assert_select "template iframe[src=?]", "https://www.youtube.com/embed/dQw4w9WgXcQ"
  end

  private
    def create_blog_post(title:, status:, published_at: nil, youtube_video_urls: [])
      BlogPost.create!(
        title: title,
        teaser: "#{title} teaser",
        body: "<div>#{title} body</div>",
        author: @author,
        status: status,
        published_at: published_at,
        published_by: (status == "published" ? @author : nil),
        youtube_video_urls: youtube_video_urls
      )
    end
end
