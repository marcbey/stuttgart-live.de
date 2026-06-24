module Public
  class NewsController < ApplicationController
    allow_unauthenticated_access only: %i[index show]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    PER_PAGE = 11

    def index
      assign_blog_posts_page

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @blog_post = BlogPost.published_live.with_rich_text_body_and_embeds.with_attached_cover_image.find_by!(slug: params[:slug])
    end

    private
      def assign_blog_posts_page
        @offset = [ params[:offset].to_i, 0 ].max
        records = BlogPost.published_live.with_attached_cover_image.offset(@offset).limit(PER_PAGE + 1).to_a

        @blog_posts = records.first(PER_PAGE)
        @has_more_blog_posts = records.size > PER_PAGE
        @next_offset = @offset + @blog_posts.size
      end

      def render_not_found
        render plain: "Nicht gefunden", status: :not_found
      end
  end
end
