module Public
  class LegacyBlogRedirectsController < ApplicationController
    allow_unauthenticated_access only: :show
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    def show
      blog_post = BlogPost.find_live_by_source_path!(request.path)
      redirect_to news_path(blog_post.slug), status: :moved_permanently
    end

    private
      def render_not_found
        render plain: "Nicht gefunden", status: :not_found
      end
  end
end
