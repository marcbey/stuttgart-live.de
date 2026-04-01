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

    def blog_post_image_copyright(blog_post, slot)
      blog_post.public_send("#{slot}_copyright")
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
    assert_equal "17.03.2026 von Autor Eins", presenter.meta_line
    assert_equal "https://cdn.example.test/news-cover.webp", presenter.hero_image_source
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
    assert_nil presenter.hero_image_credit
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
