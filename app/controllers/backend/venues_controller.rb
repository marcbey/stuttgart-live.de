module Backend
  class VenuesController < BaseController
    EditorState = Data.define(:id, :venues, :selected_venue)
    SORT_OPTIONS = %w[alphabetical total upcoming created_at].freeze

    before_action :set_filters, only: [ :index, :new, :create, :edit, :update ]
    before_action :set_venue, only: [ :edit, :update, :destroy ]

    def index
      @venues = venues_with_counts(query: @query_filter)
      @selected_venue = selected_venue_from(@venues)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def new
      @venue = Venue.new

      return render_editor_panel(@venue, query: @query_filter) if turbo_frame_request?

      redirect_to backend_venues_path(query: @query_filter.presence, sort: sort_param_for_url, new: "1")
    end

    def create
      @venue = Venue.new(venue_params)

      if @venue.save
        respond_with_editor_state(editor_state_for(@venue), notice: "Venue wurde angelegt.")
      else
        flash.now[:alert] = "Venue konnte nicht angelegt werden."
        render_invalid_state(@venue)
      end
    end

    def edit
      return render_editor_panel(@venue, query: @query_filter) if turbo_frame_request?

      redirect_to backend_venues_path(query: @query_filter.presence, sort: sort_param_for_url, venue_id: @venue.id)
    end

    def update
      if @venue.update(venue_params)
        respond_with_editor_state(editor_state_for(@venue), notice: "Venue wurde gespeichert.")
      else
        flash.now[:alert] = "Venue konnte nicht aktualisiert werden."
        render_invalid_state(@venue)
      end
    end

    def destroy
      if @venue.destroy
        redirect_to backend_venues_path(query: current_query.presence, sort: sort_param_for_url(current_sort)), notice: "Venue wurde gelöscht."
      else
        redirect_to backend_venues_path(query: current_query.presence, sort: sort_param_for_url(current_sort)), alert: @venue.errors.full_messages.to_sentence.presence || "Venue konnte nicht gelöscht werden."
      end
    end

    def autocomplete
      venues = Venue.search_by_query(params[:q], limit: autocomplete_limit)
      render json: venues.map { |venue| autocomplete_payload_for(venue) }
    end

    private
      def set_filters
        @query_filter = current_query
        @sort_filter = current_sort
      end

      def set_venue
        @venue = Venue.includes(logo_attachment: :blob).find(params[:id])
      end

      def venue_params
        params.require(:venue).permit(:name, :description, :external_url, :address, :logo, :remove_logo)
      end

      def current_query
        params[:query].to_s.strip.presence
      end

      def selected_venue_from(venues)
        return Venue.new if new_panel_requested?

        selected_id = params[:venue_id].to_i
        return venues.find { |venue| venue.id == selected_id } if selected_id.positive? && venues.any?

        if selected_id.positive? && @query_filter.blank?
          return Venue.includes(logo_attachment: :blob).find_by(id: selected_id)
        end

        venues.first
      end

      def new_panel_requested?
        ActiveModel::Type::Boolean.new.cast(params[:new])
      end

      def venues_with_counts(query:)
        quoted_now = ActiveRecord::Base.connection.quote(Time.current)

        Venue
          .includes(logo_attachment: :blob)
          .left_joins(:events)
          .group("venues.id")
          .select(
            "venues.*",
            "COUNT(events.id) AS events_count",
            "COUNT(CASE WHEN events.start_at >= #{quoted_now} THEN 1 END) AS upcoming_events_count"
          )
          .filter_by_query(query)
          .reorder(Arel.sql(sort_order_sql))
      end

      def current_sort
        sort = params[:sort].to_s
        SORT_OPTIONS.include?(sort) ? sort : "alphabetical"
      end

      def sort_order_sql
        case @sort_filter
        when "total"
          "COUNT(events.id) DESC, LOWER(venues.name) ASC, venues.id ASC"
        when "upcoming"
          "COUNT(CASE WHEN events.start_at >= #{ActiveRecord::Base.connection.quote(Time.current)} THEN 1 END) DESC, COUNT(events.id) DESC, LOWER(venues.name) ASC, venues.id ASC"
        when "created_at"
          "venues.updated_at DESC, venues.created_at DESC, venues.id DESC"
        else
          "LOWER(venues.name) ASC, venues.id ASC"
        end
      end

      def sort_param_for_url(sort = @sort_filter)
        sort == "alphabetical" ? nil : sort
      end

      def render_invalid_state(venue)
        respond_to do |format|
          format.html do
            @venues = venues_with_counts(query: @query_filter)
            @selected_venue = venue
            render :index, status: :unprocessable_entity
          end
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "venue_editor",
                partial: "backend/venues/editor_frame",
                locals: editor_frame_locals(venue, query: @query_filter)
              )
            ], status: :unprocessable_entity
          end
        end
      end

      def render_editor_panel(venue, query:)
        render partial: "backend/venues/editor_frame",
               locals: editor_frame_locals(venue, query:)
      end

      def respond_with_editor_state(editor_state, notice:)
        respond_to do |format|
          format.html do
            redirect_to backend_venues_path(
              query: @query_filter.presence,
              sort: sort_param_for_url,
              venue_id: editor_state.id
            ), notice: notice
          end
          format.turbo_stream do
            flash.now[:notice] = notice
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "venues_list",
                partial: "backend/venues/venues_list",
                locals: {
                  venues: editor_state.venues,
                  selected_venue: editor_state.selected_venue,
                  query_filter: @query_filter,
                  sort_filter: @sort_filter
                }
              ),
              turbo_stream.replace(
                "venue_editor",
                partial: "backend/venues/editor_frame",
                locals: editor_frame_locals(editor_state.selected_venue, query: @query_filter)
              )
            ]
          end
        end
      end

      def editor_state_for(target_venue)
        venues = venues_with_counts(query: @query_filter)
        selected_venue = venues.find { |venue| venue.id == target_venue.id }
        selected_venue ||= target_venue if @query_filter.blank?
        selected_venue ||= venues.first

        EditorState.new(
          id: selected_venue&.id,
          venues: venues,
          selected_venue: selected_venue
        )
      end

      def editor_frame_locals(venue, query:)
        {
          venue: venue,
          query_filter: query
        }
      end

      def autocomplete_limit
        [ params[:limit].to_i, 20 ].select(&:positive?).first || 8
      end

      def autocomplete_payload_for(venue)
        {
          id: venue.id,
          name: venue.name,
          address: venue.address.to_s.strip.presence
        }.compact
      end
  end
end
