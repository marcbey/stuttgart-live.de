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
      venues = canonical_autocomplete_venues(params[:q])
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
        venues = Venue.includes(logo_attachment: :blob).to_a
        aliases_by_canonical_id = alias_venues_by_canonical_id(venues)
        hidden_alias_ids = aliases_by_canonical_id.values.flatten.map(&:id)
        visible_venues = venues.reject { |venue| hidden_alias_ids.include?(venue.id) }
        visible_venues = filter_canonical_venues_by_query(visible_venues, aliases_by_canonical_id, query)

        assign_aggregated_counts!(visible_venues, aliases_by_canonical_id)
        sort_venues(visible_venues)
      end

      def current_sort
        sort = params[:sort].to_s
        SORT_OPTIONS.include?(sort) ? sort : "alphabetical"
      end

      def canonical_autocomplete_venues(query)
        Venue.canonical_search_by_query(query, limit: autocomplete_limit)
      end

      def alias_venues_by_canonical_id(venues)
        venues.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |venue, aliases|
          canonical = Venue.canonical_alias_venue_for(venue.name)
          next if canonical.blank? || canonical.id == venue.id

          aliases[canonical.id] << venue
        end
      end

      def filter_canonical_venues_by_query(venues, aliases_by_canonical_id, query)
        normalized_query = query.to_s.strip.downcase
        return venues if normalized_query.blank?

        venues.select do |venue|
          venue_matches_query?(venue, normalized_query) ||
            aliases_by_canonical_id.fetch(venue.id, []).any? { |alias_venue| venue_matches_query?(alias_venue, normalized_query) }
        end
      end

      def venue_matches_query?(venue, normalized_query)
        [
          venue.name,
          venue.address,
          venue.description,
          venue.external_url
        ].any? { |value| value.to_s.downcase.include?(normalized_query) }
      end

      def assign_aggregated_counts!(venues, aliases_by_canonical_id)
        venue_ids = venues.flat_map { |venue| [ venue.id, *aliases_by_canonical_id.fetch(venue.id, []).map(&:id) ] }.uniq
        total_counts = Event.where(venue_id: venue_ids).group(:venue_id).count
        upcoming_counts = Event.where(venue_id: venue_ids).where("start_at >= ?", Time.current).group(:venue_id).count

        venues.each do |venue|
          related_ids = [ venue.id, *aliases_by_canonical_id.fetch(venue.id, []).map(&:id) ]
          total_count = related_ids.sum { |venue_id| total_counts.fetch(venue_id, 0) }
          upcoming_count = related_ids.sum { |venue_id| upcoming_counts.fetch(venue_id, 0) }

          venue.define_singleton_method(:events_count) { total_count }
          venue.define_singleton_method(:upcoming_events_count) { upcoming_count }
        end
      end

      def sort_venues(venues)
        case @sort_filter
        when "total"
          venues.sort_by { |venue| [ -venue.events_count, venue.name.to_s.downcase, venue.id ] }
        when "upcoming"
          venues.sort_by { |venue| [ -venue.upcoming_events_count, -venue.events_count, venue.name.to_s.downcase, venue.id ] }
        when "created_at"
          venues.sort_by { |venue| [ -venue.updated_at.to_f, -venue.created_at.to_f, -venue.id ] }
        else
          venues.sort_by { |venue| [ venue.name.to_s.downcase, venue.id ] }
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
