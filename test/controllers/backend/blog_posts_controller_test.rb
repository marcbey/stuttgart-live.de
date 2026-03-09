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

  test "turbo frame edit renders editor panel" do
    sign_in_as(@editor)
    blog_post = create_blog_post(author: @editor)

    get edit_backend_blog_post_url(blog_post), headers: { "Turbo-Frame" => "blog_editor" }

    assert_response :success
    assert_select "turbo-frame#blog_editor"
    assert_select ".editor-panel.blog-editor-panel"
    assert_select "template.editor-actions-template"
    assert_select "form.editor-form"
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
    def create_blog_post(author:, status: "draft", published_at: nil, published_by: nil)
      BlogPost.create!(
        title: "Blogpost #{SecureRandom.hex(4)}",
        teaser: "Ein kurzer Teaser für den Beitrag.",
        body: "<div>Ein Inhalt mit Substanz.</div>",
        author: author,
        status: status,
        published_at: published_at,
        published_by: published_by
      )
    end
end
