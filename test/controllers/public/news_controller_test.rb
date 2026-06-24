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
    assert_select "meta[name='description'][content=?]", "Aktuelle News, Konzertankündigungen und Vorverkäufe von Stuttgart Live."
    assert_select "link[rel='canonical'][href=?]", news_index_url
    assert_select ".app-nav-links .app-nav-link-active", text: "News"
    assert_includes response.body, "Aktuelle News"
    assert_includes response.body, @live_post.title
    assert_not_includes response.body, @draft_post.title
    assert_not_includes response.body, @scheduled_post.title
  end

  test "index does not render an inline newsletter signup slot" do
    8.times do |index|
      create_blog_post(
        title: "Weitere News #{index}",
        status: "published",
        published_at: (index + 3).hours.ago
      )
    end

    get news_index_url

    assert_response :success
    assert_select ".news-index-newsletter-slot", count: 0
  end

  test "index renders the first eleven live posts with load more button" do
    blog_posts = 14.times.map do |index|
      create_blog_post(
        title: "Paged News #{index}",
        status: "published",
        published_at: (index + 3).hours.ago
      )
    end

    get news_index_url

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    titles = document.css(".news-index-card:not(.news-index-card-newsletter) h2").map(&:text)
    more_link = document.at_css("#news-index-more a")

    assert_equal [ @live_post.title, *blog_posts.first(10).map(&:title) ], titles
    assert_not_includes titles, blog_posts[10].title
    assert_equal "Mehr laden", more_link&.text&.strip
    assert_equal news_index_path(offset: 11, format: :turbo_stream), more_link&.[]("href")
    assert_equal "true", more_link&.[]("data-turbo-stream")
  end

  test "index hides load more button when there are no additional posts" do
    10.times do |index|
      create_blog_post(
        title: "Limited News #{index}",
        status: "published",
        published_at: (index + 3).hours.ago
      )
    end

    get news_index_url

    assert_response :success
    assert_select "#news-index-more a", count: 0
  end

  test "index turbo stream appends the next eleven live posts" do
    blog_posts = 25.times.map do |index|
      create_blog_post(
        title: "Stream News #{index}",
        status: "published",
        published_at: (index + 3).hours.ago
      )
    end

    get news_index_url(offset: 11), as: :turbo_stream

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    append_stream = document.at_css("turbo-stream[action='append'][target='news-index-grid']")
    replace_stream = document.at_css("turbo-stream[action='replace'][target='news-index-more']")
    appended_titles = append_stream.css(".news-index-card:not(.news-index-card-newsletter) h2").map(&:text)
    next_more_link = replace_stream.at_css("a")

    assert_equal blog_posts[10, 11].map(&:title), appended_titles
    assert_equal news_index_path(offset: 22, format: :turbo_stream), next_more_link&.[]("href")
    assert_select "turbo-stream[action='append'][target='news-index-grid'] .news-index-card-newsletter", count: 0
  end

  test "show renders a published post" do
    get news_url(@live_post.slug)

    assert_response :success
    assert_includes response.body, @live_post.title
    assert_includes response.body, @live_post.teaser
    assert_includes response.body, @live_post.display_author_name
    assert_select ".event-detail-back a[href='#{news_index_path}'][aria-label='Zurück']"
    assert_select "h2", text: "Artikel", count: 0
    assert_select ".event-detail-meta-line", text: /\d{2}\.\d{2}\.\d{4} von #{@live_post.display_author_name}/
  end

  test "show includes edit link for authenticated blog users" do
    sign_in_as(users(:blogger))

    get news_url(@live_post.slug)

    assert_response :success
    assert_select ".public-backend-shortcut.button.event-detail-edit-link[href='#{edit_backend_blog_post_path(@live_post)}']",
                  text: "Edit"
    assert_no_match(/Bearbeiten/, response.body)
  end

  test "index does not render cover images" do
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    get news_index_url

    assert_response :success
    assert_no_match(/news-cover\.png/, response.body)
    assert_select ".news-card-media", count: 0
  end

  test "show renders optimized cover images" do
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    get news_url(@live_post.slug)

    assert_response :success
    assert_includes response.body, rails_storage_proxy_path(@live_post.processed_optimized_image_variant(:cover_image), only_path: true)
  end

  test "show renders media proxy urls for public cover images when enabled" do
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    with_media_proxy do
      get news_url(@live_post.slug)
    end

    assert_response :success
    assert_match %r{/media/\d+/[-A-Za-z0-9_]+/.+--news-cover\.webp}, response.body
  end

  test "show renders hero image with shared event detail figure markup and crop inline styles" do
    @live_post.update!(cover_image_focus_x: 20, cover_image_focus_y: 80, cover_image_zoom: 180)
    @live_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 2000, height: 1500)),
      filename: "news-cover.png",
      content_type: "image/png"
    )

    get news_url(@live_post.slug)

    assert_response :success
    assert_select ".event-detail-image-wrap .event-detail-image-figure", count: 1
    assert_select ".event-detail-image-wrap .event-detail-image-stage", count: 1
    assert_select ".event-detail-image-wrap .event-detail-image-picture img.event-detail-image[style*='object-fit: cover']", count: 1
    assert_match(/object-fit: cover/, response.body)
    assert_match(/left: 0%/, response.body)
    assert_match(/top: -?\d+(\.\d+)?%/, response.body)
    assert_match(/width: \d+(\.\d+)?%/, response.body)
    assert_match(/height: \d+(\.\d+)?%/, response.body)
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

  test "show renders embedded rich text images through media proxy when enabled" do
    blob = create_uploaded_blob(filename: "body-image.png", width: 640, height: 480)
    @live_post.update!(
      body: %(<div>Text</div><action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>),
      published_at: Time.zone.local(2026, 4, 8, 10, 0, 0)
    )

    expected_path = nil

    travel_to Time.zone.local(2026, 4, 9, 10, 0, 0) do
      with_media_proxy do
        get news_url(@live_post.slug)
        expected_path = PublicMediaUrl.path_for(blob.representation(resize_to_limit: [ 1024, 768 ]).processed)
      end
    end

    assert_response :success
    assert_includes response.body, expected_path
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
