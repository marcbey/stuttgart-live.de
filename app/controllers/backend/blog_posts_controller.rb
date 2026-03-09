module Backend
  class BlogPostsController < BlogBaseController
    FILTERS = %w[all draft published].freeze

    before_action :set_blog_post, only: %i[edit update destroy]

    def index
      @status_filter = current_filter
      @blog_posts = filtered_blog_posts
    end

    def new
      @blog_post = current_user.authored_blog_posts.build(status: "draft")
    end

    def create
      @blog_post = current_user.authored_blog_posts.build(blog_post_params)
      apply_publication_state!(@blog_post)

      if @blog_post.save
        purge_cover_image_if_requested!(@blog_post)
        redirect_to edit_backend_blog_post_path(@blog_post), notice: creation_notice
      else
        flash.now[:alert] = "Beitrag konnte nicht gespeichert werden."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      @blog_post.assign_attributes(blog_post_params)
      apply_publication_state!(@blog_post)

      if @blog_post.save
        purge_cover_image_if_requested!(@blog_post)
        redirect_to edit_backend_blog_post_path(@blog_post), notice: update_notice
      else
        flash.now[:alert] = "Beitrag konnte nicht gespeichert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @blog_post.destroy!
      redirect_to backend_blog_posts_path(status: current_filter), notice: "Beitrag wurde gelöscht."
    end

    private
      def set_blog_post
        @blog_post = BlogPost.with_rich_text_body_and_embeds.includes(:author, :published_by).with_attached_cover_image.find(params[:id])
      end

      def current_filter
        value = params[:status].to_s
        FILTERS.include?(value) ? value : "all"
      end

      def filtered_blog_posts
        scope = BlogPost.ordered_for_backend
        return scope if current_filter == "all"

        scope.where(status: current_filter)
      end

      def blog_post_params
        params.require(:blog_post).permit(:title, :teaser, :slug, :body, :cover_image, :published_at)
      end

      def publication_action
        value = params[:publication_action].to_s
        %w[save publish depublish].include?(value) ? value : "save"
      end

      def apply_publication_state!(blog_post)
        case publication_action
        when "publish"
          blog_post.status = "published"
          blog_post.published_at ||= Time.current
          blog_post.published_by = current_user
        when "depublish"
          blog_post.status = "draft"
          blog_post.published_at = nil
          blog_post.published_by = nil
        else
          blog_post.status ||= "draft"
          blog_post.published_by = nil if blog_post.status == "draft"
        end
      end

      def remove_cover_image_requested?
        ActiveModel::Type::Boolean.new.cast(params.dig(:blog_post, :remove_cover_image))
      end

      def cover_image_upload_present?
        params.dig(:blog_post, :cover_image).present?
      end

      def purge_cover_image_if_requested!(blog_post)
        return unless remove_cover_image_requested?
        return if cover_image_upload_present?
        return unless blog_post.cover_image.attached?

        blog_post.cover_image.purge_later
      end

      def creation_notice
        publication_action == "publish" ? "Beitrag wurde veröffentlicht." : "Beitrag wurde gespeichert."
      end

      def update_notice
        case publication_action
        when "publish"
          "Beitrag wurde veröffentlicht."
        when "depublish"
          "Beitrag wurde depubliziert."
        else
          "Beitrag wurde gespeichert."
        end
      end
  end
end
