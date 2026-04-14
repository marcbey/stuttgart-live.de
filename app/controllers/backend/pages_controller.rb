module Backend
  class PagesController < BaseController
    EditorState = Data.define(:id, :pages, :selected_page)

    before_action :set_filters, only: %i[index new create edit update]
    before_action :set_page, only: %i[edit update destroy]

    def index
      @pages = filtered_pages(query: @query_filter)
      @selected_page = selected_page_from(@pages)
    end

    def new
      @page = StaticPage.new

      return render_editor_panel(@page, query: @query_filter) if turbo_frame_request?

      redirect_to backend_pages_path(query: @query_filter.presence, new: "1")
    end

    def create
      @page = StaticPage.new(page_params)

      if @page.save
        respond_with_editor_state(editor_state_for(@page), notice: "Seite wurde angelegt.")
      else
        flash.now[:alert] = "Seite konnte nicht angelegt werden."
        render_invalid_state(@page)
      end
    end

    def edit
      return render_editor_panel(@page, query: @query_filter) if turbo_frame_request?

      redirect_to backend_pages_path(query: @query_filter.presence, page_id: @page.id)
    end

    def update
      if @page.update(page_params)
        respond_with_editor_state(editor_state_for(@page), notice: "Seite wurde gespeichert.")
      else
        flash.now[:alert] = "Seite konnte nicht gespeichert werden."
        render_invalid_state(@page)
      end
    end

    def destroy
      if @page.destroy
        redirect_to backend_pages_path(query: current_query.presence), notice: "Seite wurde gelöscht."
      else
        redirect_to backend_pages_path(query: current_query.presence), alert: @page.errors.full_messages.to_sentence.presence || "Seite konnte nicht gelöscht werden."
      end
    end

    private
      def set_filters
        @query_filter = current_query
      end

      def set_page
        @page = StaticPage.with_page_content.find(params[:id])
      end

      def current_query
        params[:query].to_s.strip.presence
      end

      def filtered_pages(query:)
        relation = StaticPage.with_page_content.order(:title, :id)
        return relation if query.blank?

        token = "%#{StaticPage.sanitize_sql_like(query.downcase)}%"

        relation.where(
          <<~SQL.squish,
            LOWER(static_pages.title) LIKE :token
            OR LOWER(static_pages.slug) LIKE :token
            OR LOWER(COALESCE(static_pages.kicker, '')) LIKE :token
            OR LOWER(COALESCE(static_pages.intro, '')) LIKE :token
          SQL
          token:
        )
      end

      def selected_page_from(pages)
        return StaticPage.new if new_panel_requested?

        selected_id = params[:page_id].to_i
        return pages.find { |page| page.id == selected_id } if selected_id.positive?

        pages.first
      end

      def new_panel_requested?
        ActiveModel::Type::Boolean.new.cast(params[:new])
      end

      def render_invalid_state(page)
        respond_to do |format|
          format.html do
            @pages = filtered_pages(query: @query_filter)
            @selected_page = page
            render :index, status: :unprocessable_entity
          end
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "page_editor",
                partial: "backend/pages/editor_frame",
                locals: editor_frame_locals(page, query: @query_filter)
              )
            ], status: :unprocessable_entity
          end
        end
      end

      def render_editor_panel(page, query:)
        render partial: "backend/pages/editor_frame",
               locals: editor_frame_locals(page, query:)
      end

      def respond_with_editor_state(editor_state, notice:)
        respond_to do |format|
          format.html do
            redirect_to backend_pages_path(
              query: @query_filter.presence,
              page_id: editor_state.id
            ), notice: notice
          end
          format.turbo_stream do
            flash.now[:notice] = notice
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "pages_list",
                partial: "backend/pages/pages_list",
                locals: {
                  pages: editor_state.pages,
                  selected_page: editor_state.selected_page,
                  query_filter: @query_filter
                }
              ),
              turbo_stream.replace(
                "page_editor",
                partial: "backend/pages/editor_frame",
                locals: editor_frame_locals(editor_state.selected_page, query: @query_filter)
              )
            ]
          end
        end
      end

      def editor_state_for(target_page)
        pages = filtered_pages(query: @query_filter)
        selected_page = pages.find { |page| page.id == target_page.id } || pages.first

        EditorState.new(
          id: selected_page&.id,
          pages: pages,
          selected_page: selected_page
        )
      end

      def editor_frame_locals(page, query:)
        {
          page: page,
          query_filter: query
        }
      end

      def page_params
        params.require(:static_page).permit(:slug, :title, :kicker, :intro, :body)
      end
  end
end
