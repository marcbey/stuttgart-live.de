module Backend
  class VenuesController < BaseController
    before_action :set_venue, only: [ :edit, :update, :destroy ]

    def index
      @query_filter = current_query
      @venues = venues_with_counts(query: @query_filter)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def new
      @venue = Venue.new
    end

    def create
      @venue = Venue.new(venue_params)

      if @venue.save
        redirect_to edit_backend_venue_path(@venue, query: current_query), notice: "Venue wurde angelegt."
      else
        flash.now[:alert] = "Venue konnte nicht angelegt werden."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @venue.update(venue_params)
        redirect_to edit_backend_venue_path(@venue, query: current_query), notice: "Venue wurde gespeichert."
      else
        flash.now[:alert] = "Venue konnte nicht aktualisiert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @venue.destroy
        redirect_to backend_venues_path, notice: "Venue wurde gelöscht."
      else
        redirect_to backend_venues_path, alert: @venue.errors.full_messages.to_sentence.presence || "Venue konnte nicht gelöscht werden."
      end
    end

    def autocomplete
      venues = Venue.search_by_query(params[:q], limit: autocomplete_limit)
      render json: venues.map { |venue| autocomplete_payload_for(venue) }
    end

    private

    def set_venue
      @venue = Venue.includes(logo_attachment: :blob).find(params[:id])
    end

    def venue_params
      params.require(:venue).permit(:name, :description, :external_url, :address, :logo, :remove_logo)
    end

    def current_query
      params[:query].to_s.strip.presence
    end

    def venues_with_counts(query:)
      return Venue.none if query.blank?

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
