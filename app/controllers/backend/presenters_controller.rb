module Backend
  class PresentersController < BaseController
    EditorState = Data.define(:id, :presenters, :selected_presenter)
    SORT_OPTIONS = %w[alphabetical total created_at].freeze

    before_action :set_filters, only: %i[index new create edit update]
    before_action :set_presenter, only: [ :edit, :update, :destroy ]

    def index
      @presenters = filtered_presenters(query: @query_filter, sort: @sort_filter)
      @selected_presenter = selected_presenter_from(@presenters)
      @selected_presenter_linked_events = linked_events_for(@selected_presenter)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def new
      @presenter = Presenter.new

      return render_editor_panel(@presenter, query: @query_filter) if turbo_frame_request?

      redirect_to backend_presenters_path(query: @query_filter.presence, sort: sort_param_for_url, new: "1")
    end

    def bulk_new
      @bulk_import_result = nil
    end

    def create
      @presenter = Presenter.new(presenter_params)

      if @presenter.save
        respond_with_editor_state(editor_state_for(@presenter), notice: "Präsentator wurde angelegt.")
      else
        flash.now[:alert] = "Präsentator konnte nicht angelegt werden."
        render_invalid_state(@presenter)
      end
    end

    def bulk_create
      @bulk_import_result = Backend::Presenters::BulkImporter.new(files: bulk_upload_files).call

      if @bulk_import_result.total_processed.zero?
        flash.now[:alert] = "Bitte mindestens eine Datei auswählen."
        render :bulk_new, status: :unprocessable_entity
      elsif @bulk_import_result.any_errors?
        flash.now[:alert] = "Einige Logos konnten nicht importiert werden."
        render :bulk_new, status: :unprocessable_entity
      else
        redirect_to backend_presenters_path, notice: bulk_import_notice
      end
    end

    def edit
      return render_editor_panel(@presenter, query: @query_filter) if turbo_frame_request?

      redirect_to backend_presenters_path(query: @query_filter.presence, sort: sort_param_for_url, presenter_id: @presenter.id)
    end

    def update
      if @presenter.update(presenter_params)
        respond_with_editor_state(editor_state_for(@presenter), notice: "Präsentator wurde aktualisiert.")
      else
        flash.now[:alert] = "Präsentator konnte nicht aktualisiert werden."
        render_invalid_state(@presenter)
      end
    end

    def destroy
      if @presenter.event_presenters.exists?
        redirect_to backend_presenters_path(query: current_query.presence, sort: sort_param_for_url(current_sort)), alert: "Präsentator ist noch Events zugeordnet und kann nicht gelöscht werden."
        return
      end

      if @presenter.destroy
        redirect_to backend_presenters_path(query: current_query.presence, sort: sort_param_for_url(current_sort)), notice: "Präsentator wurde gelöscht."
      else
        redirect_to backend_presenters_path(query: current_query.presence, sort: sort_param_for_url(current_sort)), alert: @presenter.errors.full_messages.to_sentence.presence || "Präsentator konnte nicht gelöscht werden."
      end
    end

    private
      def set_filters
        @query_filter = current_query
        @sort_filter = current_sort
      end

      def set_presenter
        @presenter = Presenter.with_attached_logo.includes(event_presenters: :event).find(params[:id])
      end

      def current_query
        params[:query].to_s.strip.presence
      end

      def filtered_presenters(query:, sort:)
        relation = Presenter
          .with_attached_logo
          .includes(event_presenters: :event)
          .left_joins(:event_presenters)
          .group("presenters.id")
          .select("presenters.*", "COUNT(event_presenters.id) AS events_count")
          .reorder(Arel.sql(sort_order_sql(sort)))
        return relation if query.blank?

        token = "%#{Presenter.sanitize_sql_like(query.downcase)}%"

        relation.where(
          <<~SQL.squish,
            LOWER(presenters.name) LIKE :token
            OR LOWER(COALESCE(presenters.description, '')) LIKE :token
            OR LOWER(COALESCE(presenters.external_url, '')) LIKE :token
          SQL
          token:
        )
      end

      def selected_presenter_from(presenters)
        return Presenter.new if new_panel_requested?

        selected_id = params[:presenter_id].to_i
        return presenters.find { |presenter| presenter.id == selected_id } if selected_id.positive?

        presenters.first
      end

      def new_panel_requested?
        ActiveModel::Type::Boolean.new.cast(params[:new])
      end

      def current_sort
        sort = params[:sort].to_s
        SORT_OPTIONS.include?(sort) ? sort : "alphabetical"
      end

      def sort_order_sql(sort)
        case sort
        when "total"
          "COUNT(event_presenters.id) DESC, LOWER(presenters.name) ASC, presenters.id ASC"
        when "created_at"
          "presenters.updated_at DESC, presenters.created_at DESC, presenters.id DESC"
        else
          "LOWER(presenters.name) ASC, presenters.id ASC"
        end
      end

      def sort_param_for_url(sort = @sort_filter)
        sort == "alphabetical" ? nil : sort
      end

      def render_invalid_state(presenter)
        respond_to do |format|
          format.html do
            @presenters = filtered_presenters(query: @query_filter, sort: @sort_filter)
            @selected_presenter = presenter
            @selected_presenter_linked_events = linked_events_for(@selected_presenter)
            render :index, status: :unprocessable_entity
          end
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "presenter_editor",
                partial: "backend/presenters/editor_frame",
                locals: editor_frame_locals(presenter, query: @query_filter, sort: @sort_filter)
              )
            ], status: :unprocessable_entity
          end
        end
      end

      def render_editor_panel(presenter, query:, sort: @sort_filter)
        render partial: "backend/presenters/editor_frame",
               locals: editor_frame_locals(presenter, query:, sort:)
      end

      def respond_with_editor_state(editor_state, notice:)
        respond_to do |format|
          format.html do
            redirect_to backend_presenters_path(
              query: @query_filter.presence,
              sort: sort_param_for_url,
              presenter_id: editor_state.id
            ), notice: notice
          end
          format.turbo_stream do
            flash.now[:notice] = notice
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "presenters_list",
                partial: "backend/presenters/presenters_list",
                locals: {
                  presenters: editor_state.presenters,
                  selected_presenter: editor_state.selected_presenter,
                  query_filter: @query_filter,
                  sort_filter: @sort_filter
                }
              ),
              turbo_stream.replace(
                "presenter_editor",
                partial: "backend/presenters/editor_frame",
                locals: editor_frame_locals(editor_state.selected_presenter, query: @query_filter, sort: @sort_filter)
              )
            ]
          end
        end
      end

      def editor_state_for(target_presenter)
        presenters = filtered_presenters(query: @query_filter, sort: @sort_filter)
        selected_presenter = presenters.find { |presenter| presenter.id == target_presenter.id } || presenters.first

        EditorState.new(
          id: selected_presenter&.id,
          presenters: presenters,
          selected_presenter: selected_presenter
        )
      end

      def editor_frame_locals(presenter, query:, sort:)
        {
          presenter: presenter,
          query_filter: query,
          sort_filter: sort,
          linked_events: linked_events_for(presenter)
        }
      end

      def linked_events_for(presenter)
        return [] unless presenter&.persisted?

        presenter.event_presenters
          .filter_map(&:event)
          .uniq
          .sort_by { |event| [ event.start_at || Time.zone.at(0), event.id ] }
          .first(50)
      end

      def presenter_params
        params.require(:presenter).permit(:name, :description, :external_url, :logo)
      end

      def bulk_upload_files
        params.permit(presenter_logos: [], presenter_directory_logos: []).values.flatten.compact_blank
      end

      def bulk_import_notice
        parts = []
        parts << "#{@bulk_import_result.created} neu angelegt" if @bulk_import_result.created.positive?
        parts << "#{@bulk_import_result.updated} aktualisiert" if @bulk_import_result.updated.positive?
        "Logo-Import abgeschlossen: #{parts.to_sentence}."
      end
  end
end
