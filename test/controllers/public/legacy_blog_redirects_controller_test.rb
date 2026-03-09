require "test_helper"

class Public::LegacyBlogRedirectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    @live_post = create_blog_post(
      title: "Imported Live News",
      status: "published",
      published_at: 2.hours.ago,
      source_url: "https://stuttgart-live.de/blog/imported-live-news/"
    )
    @draft_post = create_blog_post(
      title: "Imported Draft News",
      status: "draft",
      source_url: "https://stuttgart-live.de/blog/imported-draft-news/"
    )
  end

  test "redirects old blog source path to news with 301" do
    get "/blog/imported-live-news"

    assert_redirected_to news_url(@live_post.slug)
    assert_response :moved_permanently
  end

  test "returns not found for non-live source path" do
    get "/blog/imported-draft-news"

    assert_response :not_found
  end

  private
    def create_blog_post(title:, status:, source_url:, published_at: nil)
      BlogPost.create!(
        title: title,
        teaser: "#{title} teaser",
        body: "<div>#{title} body</div>",
        author: @author,
        status: status,
        published_at: published_at,
        published_by: (status == "published" ? @author : nil),
        source_url: source_url
      )
    end
end
