require "test_helper"

class Editorial::BlogPostsInboxQueryTest < ActiveSupport::TestCase
  setup do
    @author = users(:one)
  end

  test "filters by status" do
    draft_post = create_blog_post(title: "Draft Query Post", status: "draft")
    published_post = create_blog_post(title: "Published Query Post", status: "published", published_at: 1.hour.ago, published_by: @author)

    result = Editorial::BlogPostsInboxQuery.new(params: { status: "published" }).call

    assert_includes result, published_post
    assert_not_includes result, draft_post
  end

  test "filters by query case insensitively across searchable fields" do
    matching_post = create_blog_post(title: "Irish Folk Night", status: "draft", author_name: "Stuttgart Live")
    create_blog_post(title: "Jazz Session", status: "draft")

    result = Editorial::BlogPostsInboxQuery.new(params: { query: "IRISH" }).call

    assert_equal [ matching_post ], result.to_a
  end

  test "ignores invalid status filters" do
    draft_post = create_blog_post(title: "Draft Query Post", status: "draft")
    published_post = create_blog_post(title: "Published Query Post", status: "published", published_at: 1.hour.ago, published_by: @author)

    result = Editorial::BlogPostsInboxQuery.new(params: { status: "archived" }).call

    assert_includes result, draft_post
    assert_includes result, published_post
  end

  private

  def create_blog_post(title:, status:, published_at: nil, published_by: nil, author_name: nil)
    BlogPost.create!(
      title: title,
      teaser: "Ein kurzer Teaser.",
      body: "<div>Ein Inhalt mit Substanz.</div>",
      author: @author,
      author_name: author_name,
      status: status,
      published_at: published_at,
      published_by: published_by
    )
  end
end
