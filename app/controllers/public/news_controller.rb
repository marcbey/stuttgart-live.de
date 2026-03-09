module Public
  class NewsController < ApplicationController
    allow_unauthenticated_access only: %i[index show]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    def index
      @blog_posts = BlogPost.published_live.with_attached_cover_image
    end

    def show
      @blog_post = BlogPost.published_live.with_rich_text_body_and_embeds.with_attached_cover_image.find_by!(slug: params[:slug])
    end

    private
      def render_not_found
        render plain: "Nicht gefunden", status: :not_found
      end
  end
end
