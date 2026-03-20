require "test_helper"

class Backend::BlogPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @blogger = users(:blogger)
  end

  test "requires authentication" do
    get backend_blog_posts_url

    assert_redirected_to new_session_url
  end

  test "blogger can access index" do
    sign_in_as(@blogger)
    blog_post = create_blog_post(author: @blogger, status: "draft")

    get backend_blog_posts_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Blog"
    assert_includes response.body, blog_post.title
    assert_includes response.body, "Blog-Inbox"
    assert_select "turbo-frame#blog_editor"
    assert_select "#blog_posts_list"
    assert_select "#blog_topbar_editor_actions a.button", text: "Open", count: 0
    assert_select "section.blog-post-image-section", count: 2
    assert_select "[data-controller='event-image-crop-preview blog-post-image-preupload']", count: 2
  end

  test "live blog post shows open button in topbar instead of editor header" do
    sign_in_as(@editor)
    blog_post = create_blog_post(author: @editor, status: "published", published_at: Time.current, published_by: @editor)

    get backend_blog_posts_url(blog_post_id: blog_post.id)

    assert_response :success
    assert_select "#blog_topbar_editor_actions a.button", text: "Open", count: 1
    assert_includes response.body, news_path(blog_post.slug)
    assert_select "#blog_editor_panel .editor-header-badges a", text: "Frontend", count: 0
  end

  test "index search is case insensitive" do
    sign_in_as(@blogger)
    matching_post = create_blog_post(author: @blogger, status: "draft", title: "Irish Folk Night")
    create_blog_post(author: @blogger, status: "draft", title: "Jazz Session")

    get backend_blog_posts_url, params: { query: "IRISH" }

    assert_response :success
    assert_includes response.body, matching_post.title
    assert_not_includes response.body, "Jazz Session"
  end

  test "blogger can create and publish a blog post" do
    sign_in_as(@blogger)

    assert_difference -> { BlogPost.count }, 1 do
      post backend_blog_posts_url, params: {
        blog_post: {
          title: "Frischer Beitrag",
          teaser: "Kurz und prägnant.",
          body: "<div>Volle Rich-Text-Power.</div>"
        },
        publication_action: "publish"
      }
    end

    blog_post = BlogPost.order(:id).last

    assert_redirected_to backend_blog_posts_url(blog_post_id: blog_post.id)
    assert_equal "published", blog_post.status
    assert_equal @blogger, blog_post.author
    assert_equal @blogger, blog_post.published_by
    assert blog_post.published_at.present?
  end

  test "editor can depublish a blog post" do
    sign_in_as(@editor)
    blog_post = create_blog_post(author: @editor, status: "published", published_at: 1.day.ago, published_by: @editor)

    patch backend_blog_post_url(blog_post), params: {
      blog_post: {
        title: blog_post.title,
        teaser: blog_post.teaser,
        slug: blog_post.slug,
        body: "<div>Jetzt wieder Entwurf.</div>"
      },
      publication_action: "depublish"
    }

    assert_redirected_to backend_blog_posts_url(blog_post_id: blog_post.id)
    assert_equal "draft", blog_post.reload.status
    assert_nil blog_post.published_at
    assert_nil blog_post.published_by
  end

  test "editor can publish a promotion banner and it replaces the previous one" do
    sign_in_as(@editor)
    previous_banner = create_blog_post(author: @editor, status: "published", published_at: 2.days.ago, published_by: @editor)
    previous_banner.promotion_banner_image.attach(png_upload(filename: "previous-banner.png"))
    previous_banner.update!(promotion_banner: true)

    blog_post = create_blog_post(author: @editor, status: "published", published_at: 1.day.ago, published_by: @editor)
    promotion_blob = create_uploaded_blob(filename: "promotion-banner.png")

    patch backend_blog_post_url(blog_post), params: {
      blog_post: {
        title: blog_post.title,
        teaser: blog_post.teaser,
        slug: blog_post.slug,
        body: "<div>Jetzt Banner.</div>",
        promotion_banner: "1",
        promotion_banner_kicker_text: "Empfehlung",
        promotion_banner_cta_text: "Jetzt lesen",
        promotion_banner_image_copyright: "Foto: Redaktion",
        promotion_banner_image_focus_x: "18",
        promotion_banner_image_focus_y: "72",
        promotion_banner_image_zoom: "140"
      },
      blog_post_images: {
        promotion_banner_image_signed_id: promotion_blob.signed_id,
        remove_promotion_banner_image: "0"
      },
      publication_action: "publish"
    }

    assert_redirected_to backend_blog_posts_url(blog_post_id: blog_post.id)
    assert_predicate blog_post.reload, :promotion_banner?
    assert_not previous_banner.reload.promotion_banner?
    assert blog_post.promotion_banner_image.attached?
    assert_equal "Empfehlung", blog_post.promotion_banner_kicker_text
    assert_equal "Jetzt lesen", blog_post.promotion_banner_cta_text
    assert_equal "Foto: Redaktion", blog_post.promotion_banner_image_copyright
    assert_equal 18.0, blog_post.promotion_banner_image_focus_x_value
    assert_equal 72.0, blog_post.promotion_banner_image_focus_y_value
    assert_equal 140.0, blog_post.promotion_banner_image_zoom_value
  end

  test "editor cannot remove the promotion banner image while the banner stays active" do
    sign_in_as(@editor)
    blog_post = create_blog_post(author: @editor, status: "published", published_at: 1.day.ago, published_by: @editor)
    blog_post.promotion_banner_image.attach(png_upload(filename: "promotion-banner.png"))
    blog_post.update!(promotion_banner: true)

    patch backend_blog_post_url(blog_post), params: {
      blog_post: {
        title: blog_post.title,
        teaser: blog_post.teaser,
        slug: blog_post.slug,
        body: "<div>Banner bleibt aktiv.</div>",
        promotion_banner: "1"
      },
      blog_post_images: {
        remove_promotion_banner_image: "1"
      },
      publication_action: "save"
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "muss für einen Promotion Banner vorhanden sein"
    assert blog_post.reload.promotion_banner_image.attached?
  end

  test "turbo publish updates topbar controls" do
    sign_in_as(@editor)
    blog_post = create_blog_post(author: @editor, status: "draft")

    patch backend_blog_post_url(blog_post), params: {
      blog_post: {
        title: blog_post.title,
        teaser: blog_post.teaser,
        slug: blog_post.slug,
        body: "<div>Jetzt publiziert.</div>"
      },
      publication_action: "publish"
    }, as: :turbo_stream

    assert_response :success
    assert_equal "published", blog_post.reload.status
    assert_includes response.body, 'target="blog_topbar_editor_actions"'
    assert_includes response.body, "Unpublish"
    assert_includes response.body, "Open"
    assert_includes response.body, 'target="blog_topbar_context"'
    assert_includes response.body, "Published"
  end

  test "turbo publish keeps active draft filter and refreshes inbox" do
    sign_in_as(@editor)
    published_from_draft = create_blog_post(author: @editor, status: "draft", title: "Will Publish")
    remaining_draft = create_blog_post(author: @editor, status: "draft", title: "Still Draft")

    patch backend_blog_post_url(published_from_draft), params: {
      status: "draft",
      blog_post: {
        title: published_from_draft.title,
        teaser: published_from_draft.teaser,
        slug: published_from_draft.slug,
        body: "<div>Jetzt publiziert.</div>"
      },
      publication_action: "publish"
    }, as: :turbo_stream

    assert_response :success
    assert_equal "published", published_from_draft.reload.status
    assert_includes response.body, 'target="blog_posts_list"'
    assert_includes response.body, remaining_draft.title
    assert_not_includes response.body, "Will Publish"
    assert_includes response.body, 'target="blog_topbar_context"'
    assert_includes response.body, remaining_draft.title
  end

  test "turbo frame edit renders editor panel" do
    sign_in_as(@editor)
    blog_post = create_blog_post(author: @editor)

    get edit_backend_blog_post_url(blog_post), headers: { "Turbo-Frame" => "blog_editor" }

    assert_response :success
    assert_select "turbo-frame#blog_editor"
    assert_select ".editor-panel.blog-editor-panel"
    assert_select "template.editor-actions-template"
    assert_select "form.editor-form"
    assert_select ".blog-editor-section-promotion"
    assert_select "input[name='blog_post[promotion_banner_kicker_text]']"
    assert_select "input[name='blog_post[promotion_banner_cta_text]']"
    assert_no_match(/Blog-Inbox/, response.body)
  end

  test "editor can delete a blog post" do
    sign_in_as(@editor)
    blog_post = create_blog_post(author: @editor)

    assert_difference -> { BlogPost.count }, -1 do
      delete backend_blog_post_url(blog_post)
    end

    assert_redirected_to backend_blog_posts_url
  end

  private
    def create_blog_post(author:, status: "draft", published_at: nil, published_by: nil, title: nil)
      BlogPost.create!(
        title: title || "Blogpost #{SecureRandom.hex(4)}",
        teaser: "Ein kurzer Teaser für den Beitrag.",
        body: "<div>Ein Inhalt mit Substanz.</div>",
        author: author,
        status: status,
        published_at: published_at,
        published_by: published_by
      )
    end
end
