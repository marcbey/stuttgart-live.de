module Backend
  class BlogPostsController < BlogBaseController
    EditorState = Data.define(:target_status, :sidebar_posts, :selected_blog_post)

    FILTERS = %w[all draft published].freeze

    before_action :set_blog_post, only: %i[edit update destroy]
    before_action :set_filters, only: %i[index new create edit update]

    def index
      @blog_posts = filtered_blog_posts_for(status: @status_filter, query: @query_filter)
      @selected_blog_post = selected_blog_post_from(@blog_posts)
    end

    def new
      @blog_post = current_user.authored_blog_posts.build(status: "draft")

      return render_editor_panel(@blog_post, status: @status_filter, query: @query_filter) if turbo_frame_request?

      redirect_to backend_blog_posts_path(status: status_param(@status_filter), query: @query_filter.presence, new: "1")
    end

    def create
      @blog_post = current_user.authored_blog_posts.build(blog_post_params)
      @blog_post.apply_publication_action(action: publication_action, user: current_user)
      prepare_blog_post_images(@blog_post)

      if @blog_post.errors.any?
        flash.now[:alert] = "Beitrag konnte nicht gespeichert werden."
        render_invalid_state(@blog_post)
      elsif @blog_post.save
        persist_blog_post_images!(@blog_post)
        render_persisted_state(target_blog_post: @blog_post, notice: creation_notice)
      else
        flash.now[:alert] = "Beitrag konnte nicht gespeichert werden."
        render_invalid_state(@blog_post)
      end
    end

    def edit
      return render_editor_panel(@blog_post, status: @status_filter, query: @query_filter) if turbo_frame_request?

      redirect_to backend_blog_posts_path(status: status_param(@status_filter), query: @query_filter.presence, blog_post_id: @blog_post.id)
    end

    def update
      @blog_post.assign_attributes(blog_post_params)
      @blog_post.apply_publication_action(action: publication_action, user: current_user)
      prepare_blog_post_images(@blog_post)

      if @blog_post.errors.any?
        flash.now[:alert] = "Beitrag konnte nicht gespeichert werden."
        render_invalid_state(@blog_post)
      elsif @blog_post.save
        persist_blog_post_images!(@blog_post)
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
        @blog_post = BlogPost.with_rich_text_body_and_embeds.includes(:author, :published_by).with_attached_cover_image.with_attached_promotion_banner_image.find(params[:id])
      end

      def set_filters
        @status_filter = current_filter
        @query_filter = current_query
      end

      def current_filter
        value = params[:status].to_s
        FILTERS.include?(value) ? value : "all"
      end

      def current_query
        params[:query].to_s.strip.presence
      end

      def filtered_blog_posts_for(status:, query:)
        Editorial::BlogPostsInboxQuery.new(
          params: {
            status: status == "all" ? nil : status,
            query: query
          }
        ).call
      end

      def selected_blog_post_from(blog_posts)
        return current_user.authored_blog_posts.build(status: "draft") if new_panel_requested?

        selected_id = params[:blog_post_id].to_i
        return blog_posts.find { |candidate| candidate.id == selected_id } if selected_id.positive?

        blog_posts.first
      end

      def blog_post_params
        params.require(:blog_post).permit(
          :title,
          :teaser,
          :slug,
          :body,
          :published_at,
          :author_name,
          :promotion_banner,
          :cover_image_copyright,
          :cover_image_focus_x,
          :cover_image_focus_y,
          :cover_image_zoom,
          :promotion_banner_image_copyright,
          :promotion_banner_image_focus_x,
          :promotion_banner_image_focus_y,
          :promotion_banner_image_zoom
        )
      end

      def publication_action
        value = params[:publication_action].to_s
        %w[save publish depublish].include?(value) ? value : "save"
      end

      def new_panel_requested?
        ActiveModel::Type::Boolean.new.cast(params[:new])
      end

      def status_param(filter)
        filter == "all" ? nil : filter
      end

      def render_persisted_state(target_blog_post:, notice:)
        respond_with_editor_state(editor_state_for(target_blog_post), notice: notice)
      end

      def prepare_blog_post_images(blog_post)
        image_params = blog_post_image_params

        blog_post.pending_cover_image_blob = resolve_signed_blob(image_params[:cover_image_signed_id], label: "Titelbild", blog_post: blog_post)
        blog_post.pending_promotion_banner_image_blob = resolve_signed_blob(image_params[:promotion_banner_image_signed_id], label: "Promotion-Banner-Bild", blog_post: blog_post)
        blog_post.remove_cover_image = remove_cover_image_requested?
        blog_post.remove_promotion_banner_image = remove_promotion_banner_image_requested?
      end

      def persist_blog_post_images!(blog_post)
        persist_blog_post_image!(
          blog_post: blog_post,
          attachment_name: :cover_image,
          pending_blob: blog_post.pending_cover_image_blob,
          remove: blog_post.remove_cover_image?
        )
        persist_blog_post_image!(
          blog_post: blog_post,
          attachment_name: :promotion_banner_image,
          pending_blob: blog_post.pending_promotion_banner_image_blob,
          remove: blog_post.remove_promotion_banner_image?
        )
      end

      def persist_blog_post_image!(blog_post:, attachment_name:, pending_blob:, remove:)
        attachment = blog_post.public_send(attachment_name)

        if pending_blob.present?
          attachment.attach(pending_blob)
        elsif remove && attachment.attached?
          attachment.purge_later
        end
      end

      def blog_post_image_params
        params.fetch(:blog_post_images, ActionController::Parameters.new).permit(
          :cover_image_signed_id,
          :promotion_banner_image_signed_id,
          :remove_cover_image,
          :remove_promotion_banner_image
        )
      end

      def remove_cover_image_requested?
        ActiveModel::Type::Boolean.new.cast(blog_post_image_params[:remove_cover_image])
      end

      def remove_promotion_banner_image_requested?
        ActiveModel::Type::Boolean.new.cast(blog_post_image_params[:remove_promotion_banner_image])
      end

      def resolve_signed_blob(signed_id, label:, blog_post:)
        return if signed_id.blank?

        ActiveStorage::Blob.find_signed!(signed_id)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        blog_post.errors.add(:base, "#{label}: Der temporäre Upload ist ungültig oder abgelaufen.")
        nil
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
                locals: editor_frame_locals(blog_post, status: @status_filter, query: @query_filter)
              )
            ], status: :unprocessable_entity
          end
        end
      end

      def render_editor_panel(blog_post, status:, query:)
        render partial: "backend/blog_posts/editor_frame",
               locals: editor_frame_locals(blog_post, status: status, query: query)
      end

      def respond_with_editor_state(editor_state, notice:)
        respond_to do |format|
          format.html do
            redirect_to backend_blog_posts_path(
              status: status_param(editor_state.target_status),
              query: @query_filter.presence,
              blog_post_id: editor_state.selected_blog_post&.id
            ), notice: notice
          end
          format.turbo_stream do
            flash.now[:notice] = notice
            render_inbox_state_turbo_stream(editor_state)
          end
        end
      end

      def render_inbox_state_turbo_stream(editor_state)
        render turbo_stream: [
          turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
          turbo_stream.replace(
            "blog_topbar_context",
            partial: "backend/blog_posts/topbar_context",
            locals: { blog_post: editor_state.selected_blog_post }
          ),
          turbo_stream.replace(
            "blog_topbar_editor_actions",
            partial: "backend/blog_posts/topbar_editor_actions",
            locals: { blog_post: editor_state.selected_blog_post }
          ),
          turbo_stream.replace(
            "blog_posts_list",
            partial: "backend/blog_posts/blog_posts_list",
            locals: {
              blog_posts: editor_state.sidebar_posts,
              selected_blog_post: editor_state.selected_blog_post,
              status_filter: editor_state.target_status,
              query_filter: @query_filter
            }
          ),
          turbo_stream.replace(
            "blog_editor",
            partial: "backend/blog_posts/editor_frame",
            locals: editor_frame_locals(editor_state.selected_blog_post, status: editor_state.target_status, query: @query_filter)
          )
        ]
      end

      def editor_frame_locals(blog_post, status:, query:)
        {
          blog_post: blog_post,
          status_filter: status,
          query_filter: query
        }
      end

      def editor_state_for(target_blog_post)
        target_status = @status_filter
        sidebar_posts = filtered_blog_posts_for(status: target_status, query: @query_filter)

        EditorState.new(
          target_status: target_status,
          sidebar_posts: sidebar_posts,
          selected_blog_post: selected_blog_post_for(sidebar_posts, preferred_blog_post: target_blog_post)
        )
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
