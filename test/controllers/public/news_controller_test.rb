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
    assert_includes response.body, @live_post.title
    assert_not_includes response.body, @draft_post.title
    assert_not_includes response.body, @scheduled_post.title
  end

  test "show renders a published post" do
    get news_url(@live_post.slug)

    assert_response :success
    assert_includes response.body, @live_post.title
    assert_includes response.body, @live_post.teaser
    assert_includes response.body, "Zurück zu News"
  end

  test "show returns not found for drafts" do
    get news_url(@draft_post.slug)

    assert_response :not_found
  end

  private
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
