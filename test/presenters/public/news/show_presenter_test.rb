require "test_helper"

class Public::News::ShowPresenterTest < ActiveSupport::TestCase
  class ViewContextStub
    def news_url(slug)
      "https://stuttgart-live.de/news/#{slug}"
    end

    def news_index_path
      "/news"
    end

    def l(value, format:)
      value.strftime(format)
    end

    def optimized_blog_post_image_url(_blog_post, _slot)
      "https://cdn.example.test/news-cover.webp"
    end

    def blog_post_cropped_image_style(_blog_post, _slot, frame_ratio:, edge_lock_margin: nil)
      "crop-style-#{frame_ratio.round(2)}-margin-#{edge_lock_margin}"
    end

    def blog_post_image_copyright(blog_post, slot)
      blog_post.public_send("#{slot}_copyright")
    end

    def asset_path(logical_path)
      "/assets/#{logical_path}"
    end
  end

  test "exposes meta and hero data" do
    blog_post = build_post(
      title: "Neue Headline",
      teaser: "Kurzbeschreibung",
      slug: "neue-headline",
      published_at: Time.zone.local(2026, 3, 17, 12, 0),
      cover_image_copyright: "Foto: Agentur"
    )
    blog_post.cover_image.attach(
      io: StringIO.new(solid_png_binary(width: 1200, height: 900)),
      filename: "cover.png",
      content_type: "image/png"
    )

    presenter = build_presenter(blog_post)

    assert_equal "Neue Headline | 17.03.2026 | News | Stuttgart Live", presenter.page_title
    assert_equal "Neue Headline | 17.03.2026 | News", presenter.meta_title
    assert_equal "Kurzbeschreibung", presenter.meta_description
    assert_equal "https://stuttgart-live.de/news/neue-headline", presenter.canonical_url
    assert_equal "https://cdn.example.test/news-cover.webp", presenter.og_image_url
    assert_equal "/news", presenter.back_path
    assert_equal "event-detail-header news-detail-header event-detail-header-with-image news-detail-header-with-image", presenter.header_classes
    assert_equal "Neue Headline", presenter.headline
    assert_equal "Kurzbeschreibung", presenter.teaser
    assert_equal "17.03.2026", presenter.meta_line
    assert_equal "Autor Eins", presenter.author_label
    assert_equal "Redaktion", presenter.author_role
    assert_nil presenter.author_image_source
    assert_equal "AE", presenter.author_initials
    assert_equal "https://cdn.example.test/news-cover.webp", presenter.hero_image_source
    assert_equal "crop-style-1.6-margin-0.06", presenter.hero_image_style
    assert_equal "aspect-ratio: 16 / 10; height: auto; min-height: 0; background: transparent; box-shadow: none", presenter.hero_stage_style
    assert_equal "inset: 0;", presenter.hero_picture_style
    assert_equal "Neue Headline", presenter.hero_alt_text
    assert_equal "Foto: Agentur", presenter.hero_image_credit
    assert presenter.has_video_block?
    assert_match(/"@type":"NewsArticle"/, presenter.schema_json_ld)
  end

  test "uses compact no-image header classes without hero image data" do
    blog_post = build_post(
      title: "Ohne Bild",
      teaser: "Kompakter Einstieg",
      slug: "ohne-bild",
      published_at: Time.zone.local(2026, 3, 18, 12, 0),
      cover_image_copyright: nil
    )

    presenter = build_presenter(blog_post)

    assert_equal "event-detail-header news-detail-header news-detail-header-no-image", presenter.header_classes
    assert_not presenter.hero_image?
    assert_nil presenter.hero_image_source
    assert_nil presenter.hero_image_style
    assert_equal "aspect-ratio: 16 / 10; height: auto; min-height: 0; background: transparent; box-shadow: none", presenter.hero_stage_style
    assert_equal "inset: 0;", presenter.hero_picture_style
    assert_nil presenter.hero_image_credit
  end

  test "uses newsletter team profile for matching author details" do
    blog_post = build_post(
      title: "Team News",
      teaser: "Aus dem Team",
      slug: "team-news",
      published_at: Time.zone.local(2026, 3, 18, 12, 0),
      cover_image_copyright: nil
    )
    blog_post.author_name = "Sarah Sandner"

    presenter = build_presenter(blog_post)

    assert_equal "Sarah Sandner", presenter.author_label
    assert_equal "Marketing", presenter.author_role
    assert_equal "/assets/newsletter/team/sarah.jpg", presenter.author_image_source
  end

  test "normalizes stored youtube embed urls for display" do
    blog_post = build_post(
      title: "Video News",
      teaser: "Video Teaser",
      slug: "video-news",
      published_at: Time.zone.local(2026, 3, 18, 12, 0),
      cover_image_copyright: nil
    )
    blog_post.youtube_video_urls = [ "https://www.youtube.com/embed/dQw4w9WgXcQ" ]

    presenter = build_presenter(blog_post)

    assert_equal [ "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" ], presenter.video_urls
  end

  private

  def build_presenter(blog_post)
    Public::News::ShowPresenter.new(blog_post, view_context: ViewContextStub.new)
  end

  def build_post(title:, teaser:, slug:, published_at:, cover_image_copyright:)
    BlogPost.new(
      title: title,
      teaser: teaser,
      slug: slug,
      published_at: published_at,
      updated_at: published_at + 1.hour,
      author_name: "Autor Eins",
      cover_image_copyright: cover_image_copyright,
      youtube_video_urls: [ "https://youtu.be/dQw4w9WgXcQ" ]
    ).tap do |blog_post|
      blog_post.body = "<div><strong>Artikeltext</strong></div>"
    end
  end
end
