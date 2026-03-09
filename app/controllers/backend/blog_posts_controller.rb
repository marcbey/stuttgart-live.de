module Backend
  class BlogPostsController < BlogBaseController
    FILTERS = %w[all draft published].freeze

    before_action :set_blog_post, only: %i[edit update destroy]

    def index
      @status_filter = current_filter
      @query_filter = current_query
      @blog_posts = filtered_blog_posts_for(status: @status_filter, query: @query_filter)
      @selected_blog_post = selected_blog_post_from(@blog_posts)
    end

    def new
      @status_filter = current_filter
      @query_filter = current_query
      @blog_post = current_user.authored_blog_posts.build(status: "draft")

      return render_editor_panel(@blog_post, status: @status_filter, query: @query_filter) if turbo_frame_request?

      redirect_to backend_blog_posts_path(status: status_param(@status_filter), query: @query_filter.presence, new: "1")
    end

    def create
      @status_filter = current_filter
      @query_filter = current_query
      @blog_post = current_user.authored_blog_posts.build(blog_post_params)
      apply_publication_state!(@blog_post)

      if @blog_post.save
        purge_cover_image_if_requested!(@blog_post)
        render_persisted_state(target_blog_post: @blog_post, notice: creation_notice)
      else
        flash.now[:alert] = "Beitrag konnte nicht gespeichert werden."
        render_invalid_state(@blog_post)
      end
    end

    def edit
      @status_filter = current_filter
      @query_filter = current_query

      return render_editor_panel(@blog_post, status: @status_filter, query: @query_filter) if turbo_frame_request?

      redirect_to backend_blog_posts_path(status: status_param(@status_filter), query: @query_filter.presence, blog_post_id: @blog_post.id)
    end

    def update
      @status_filter = current_filter
      @query_filter = current_query
      @blog_post.assign_attributes(blog_post_params)
      apply_publication_state!(@blog_post)

      if @blog_post.save
        purge_cover_image_if_requested!(@blog_post)
        render_persisted_state(target_blog_post: @blog_post, notice: update_notice)
      else
        flash.now[:alert] = "Beitrag konnte nicht gespeichert werden."
        render_invalid_state(@blog_post)
      end
    end

    def destroy
      @blog_post.destroy!
      redirect_to backend_blog_posts_path(status: status_param(current_filter), query: current_query.presence), notice: "Beitrag wurde gelöscht."
    end

    private
      def set_blog_post
        @blog_post = BlogPost.with_rich_text_body_and_embeds.includes(:author, :published_by).with_attached_cover_image.find(params[:id])
      end

      def current_filter
        value = params[:status].to_s
        FILTERS.include?(value) ? value : "all"
      end

      def current_query
        params[:query].to_s.strip.presence
      end

      def filtered_blog_posts_for(status:, query:)
        scope = BlogPost.ordered_for_backend
        scope = scope.where(status: status) unless status == "all"

        return scope if query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
        scope.where(
          "LOWER(blog_posts.title) LIKE :pattern OR LOWER(blog_posts.teaser) LIKE :pattern OR LOWER(blog_posts.slug) LIKE :pattern OR LOWER(COALESCE(blog_posts.author_name, '')) LIKE :pattern",
          pattern: pattern
        )
      end

      def selected_blog_post_from(blog_posts)
        return current_user.authored_blog_posts.build(status: "draft") if new_panel_requested?

        selected_id = params[:blog_post_id].to_i
        return blog_posts.find { |candidate| candidate.id == selected_id } if selected_id.positive?

        blog_posts.first
      end

      def blog_post_params
        params.require(:blog_post).permit(:title, :teaser, :slug, :body, :cover_image, :published_at, :author_name)
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

      def new_panel_requested?
        ActiveModel::Type::Boolean.new.cast(params[:new])
      end

      def status_param(filter)
        filter == "all" ? nil : filter
      end

      def render_persisted_state(target_blog_post:, notice:)
        target_status = current_filter
        sidebar_posts = filtered_blog_posts_for(status: target_status, query: @query_filter)
        selected_blog_post = selected_blog_post_for(sidebar_posts, preferred_blog_post: target_blog_post)

        respond_to do |format|
          format.html do
            redirect_to backend_blog_posts_path(
              status: status_param(target_status),
              query: @query_filter.presence,
              blog_post_id: selected_blog_post&.id
            ), notice: notice
          end
          format.turbo_stream do
            flash.now[:notice] = notice
            render_inbox_state_turbo_stream(
              sidebar_posts: sidebar_posts,
              selected_blog_post: selected_blog_post,
              target_status: target_status
            )
          end
        end
      end

      def render_invalid_state(blog_post)
        respond_to do |format|
          format.html do
            @selected_blog_post = blog_post
            @blog_posts = filtered_blog_posts_for(status: @status_filter, query: @query_filter)
            render :index, status: :unprocessable_entity
          end
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "blog_editor",
                partial: "backend/blog_posts/editor_frame",
                locals: {
                  blog_post: blog_post,
                  status_filter: @status_filter,
                  query_filter: @query_filter
                }
              )
            ], status: :unprocessable_entity
          end
        end
      end

      def render_editor_panel(blog_post, status:, query:)
        render partial: "backend/blog_posts/editor_frame",
               locals: {
                 blog_post: blog_post,
                 status_filter: status,
                 query_filter: query
               }
      end

      def render_inbox_state_turbo_stream(sidebar_posts:, selected_blog_post:, target_status:)
        render turbo_stream: [
          turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
          turbo_stream.replace(
            "blog_topbar_context",
            partial: "backend/blog_posts/topbar_context",
            locals: { blog_post: selected_blog_post }
          ),
          turbo_stream.replace(
            "blog_topbar_editor_actions",
            partial: "backend/blog_posts/topbar_editor_actions",
            locals: { blog_post: selected_blog_post }
          ),
          turbo_stream.replace(
            "blog_posts_list",
            partial: "backend/blog_posts/blog_posts_list",
            locals: {
              blog_posts: sidebar_posts,
              selected_blog_post: selected_blog_post,
              status_filter: target_status,
              query_filter: @query_filter
            }
          ),
          turbo_stream.replace(
            "blog_editor",
            partial: "backend/blog_posts/editor_frame",
            locals: {
              blog_post: selected_blog_post,
              status_filter: target_status,
              query_filter: @query_filter
            }
          )
        ]
      end

      def selected_blog_post_for(sidebar_posts, preferred_blog_post:)
        sidebar_posts.find { |candidate| candidate.id == preferred_blog_post.id } || sidebar_posts.first
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
