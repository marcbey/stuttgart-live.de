module Editorial
  class BlogPostsInboxQuery
    def initialize(scope: BlogPost.all, params: {})
      @scope = scope
      @params = params
    end

    def call
      relation = scope.ordered_for_backend
      relation = relation.where(status: status_filter) if status_filter.present?
      return relation if query.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
      relation.where(
        "LOWER(blog_posts.title) LIKE :pattern OR LOWER(blog_posts.teaser) LIKE :pattern OR LOWER(blog_posts.slug) LIKE :pattern OR LOWER(COALESCE(blog_posts.author_name, '')) LIKE :pattern",
        pattern: pattern
      )
    end

    private

    attr_reader :scope, :params

    def status_filter
      value = params[:status].to_s
      value if BlogPost::STATUSES.include?(value)
    end

    def query
      params[:query].to_s.strip.presence
    end
  end
end
