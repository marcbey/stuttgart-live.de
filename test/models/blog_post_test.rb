require "test_helper"

class BlogPostTest < ActiveSupport::TestCase
  setup do
    @author = users(:one)
  end

  test "generates a unique slug from the title" do
    first = BlogPost.create!(
      title: "Neue Bühne",
      teaser: "Ein Teaser.",
      body: "<div>Text</div>",
      author: @author,
      status: "draft"
    )

    second = BlogPost.create!(
      title: "Neue Bühne",
      teaser: "Noch ein Teaser.",
      body: "<div>Mehr Text</div>",
      author: @author,
      status: "draft"
    )

    assert_equal "neue-buhne", first.slug
    assert_equal "neue-buhne-2", second.slug
  end

  test "requires body content" do
    blog_post = BlogPost.new(
      title: "Ohne Inhalt",
      teaser: "Teaser",
      author: @author,
      status: "draft"
    )

    assert_not blog_post.valid?
    assert_includes blog_post.errors[:body], "muss ausgefüllt werden"
  end

  test "published_live returns only already published posts" do
    live_post = BlogPost.create!(
      title: "Live",
      teaser: "Live Teaser",
      body: "<div>Live</div>",
      author: @author,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @author
    )

    BlogPost.create!(
      title: "Später",
      teaser: "Später Teaser",
      body: "<div>Später</div>",
      author: @author,
      status: "published",
      published_at: 1.hour.from_now,
      published_by: @author
    )

    BlogPost.create!(
      title: "Entwurf",
      teaser: "Entwurf Teaser",
      body: "<div>Entwurf</div>",
      author: @author,
      status: "draft"
    )

    assert_equal [ live_post ], BlogPost.published_live.to_a
  end

  test "apply_publication_action publishes with current user" do
    blog_post = BlogPost.new(
      title: "Neu",
      teaser: "Teaser",
      body: "<div>Inhalt</div>",
      author: @author,
      status: "draft"
    )

    freeze_time do
      blog_post.apply_publication_action(action: "publish", user: @author)

      assert_equal "published", blog_post.status
      assert_equal Time.current, blog_post.published_at
      assert_equal @author, blog_post.published_by
    end
  end

  test "apply_publication_action depublishes and clears publication fields" do
    blog_post = BlogPost.new(
      title: "Neu",
      teaser: "Teaser",
      body: "<div>Inhalt</div>",
      author: @author,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @author
    )

    blog_post.apply_publication_action(action: "depublish", user: @author)

    assert_equal "draft", blog_post.status
    assert_nil blog_post.published_at
    assert_nil blog_post.published_by
  end

  test "apply_publication_action keeps draft as default on regular save" do
    blog_post = BlogPost.new(
      title: "Neu",
      teaser: "Teaser",
      body: "<div>Inhalt</div>",
      author: @author,
      status: nil
    )

    blog_post.apply_publication_action(action: "save", user: @author)

    assert_equal "draft", blog_post.status
    assert_nil blog_post.published_by
  end

  test "promotion banner requires banner image" do
    blog_post = BlogPost.new(
      title: "Banner Entwurf",
      teaser: "Teaser",
      body: "<div>Inhalt</div>",
      author: @author,
      status: "draft",
      promotion_banner: true
    )

    assert_not blog_post.valid?
    assert_includes blog_post.errors[:promotion_banner_image], "muss für einen Promotion Banner vorhanden sein"
  end

  test "promotion banner clears previous banner post" do
    first = BlogPost.create!(
      title: "Erster Banner",
      teaser: "Teaser",
      body: "<div>Inhalt</div>",
      author: @author,
      status: "published",
      published_at: 2.hours.ago,
      published_by: @author
    )
    first.promotion_banner_image.attach(png_upload(filename: "first-banner.png"))
    first.update!(promotion_banner: true)

    second = BlogPost.new(
      title: "Zweiter Banner",
      teaser: "Teaser",
      body: "<div>Inhalt</div>",
      author: @author,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @author,
      promotion_banner: true
    )
    second.promotion_banner_image.attach(png_upload(filename: "second-banner.png"))
    second.save!

    assert_predicate second.reload, :promotion_banner?
    assert_not first.reload.promotion_banner?
  end
end
