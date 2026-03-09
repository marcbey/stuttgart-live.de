module Public
  class NewsController < ApplicationController
    allow_unauthenticated_access only: %i[index show]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    def index
      @news_query = params[:q].to_s.strip
      @blog_posts = BlogPost.published_live.with_attached_cover_image
      @blog_posts = apply_query(@blog_posts, @news_query) if @news_query.present?
    end

    def show
      @blog_post = BlogPost.published_live.with_rich_text_body_and_embeds.with_attached_cover_image.find_by!(slug: params[:slug])
    end

    private
      def apply_query(relation, query)
        token = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

        relation.where(
          "blog_posts.title ILIKE :token OR blog_posts.teaser ILIKE :token",
          token: token
        )
      end

      def render_not_found
        render plain: "Nicht gefunden", status: :not_found
      end
  end
end
