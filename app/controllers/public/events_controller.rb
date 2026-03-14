module Public
  class EventsController < ApplicationController
    allow_unauthenticated_access only: [ :index, :show ]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    PER_PAGE = 12
    HOME_HIGHLIGHT_LIMIT = 100

    before_action :set_browse_state, only: [ :index, :show ]

    def index
      if genre_panel_frame_request?
        @selected_genre_tile = selected_genre_tile
        @selected_genre_events = selected_genre_events
        render partial: "public/events/genre_events_frame",
               locals: {
                 browse_state: @browse_state,
                 selected_genre_tile: @selected_genre_tile,
                 selected_genre_events: @selected_genre_events
               }
        return
      end

      relation = visible_events_relation(filter: search_filter, event_date: @browse_state.event_date, query: @browse_state.query)
      if should_redirect_search_result?(relation)
        event = relation.limit(1).first
        redirect_to event_path(event.slug, **@browse_state.route_params.except(:q))
        return
      end

      @events = relation.limit(PER_PAGE).offset((@browse_state.page - 1) * PER_PAGE)
      @next_page = @browse_state.page + 1 if relation.offset(@browse_state.page * PER_PAGE).limit(1).exists?
      homepage_relation = visible_events_relation(filter: @browse_state.filter, event_date: @browse_state.event_date, query: nil)
      assign_homepage_sections(homepage_relation) if @browse_state.page == 1

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @event = show_events_relation.find_by!(slug: params[:slug])
      @primary_offer = @event.preferred_ticket_offer
    end

    def status
      browse_state = Public::Events::BrowseState.new(params)
      @event = Event.find_by!(slug: params[:slug])
      desired_status = params[:status].to_s

      unless Event::STATUSES.include?(desired_status)
        redirect_back fallback_location: events_path(**browse_state.route_params(page: browse_state.page))
        return
      end

      apply_status!(@event, desired_status)
      Editorial::EventChangeLogger.log!(
        event: @event,
        action: "public_status_update",
        user: current_user,
        changed_fields: @event.saved_changes
      )

      respond_to do |format|
        format.turbo_stream do
          streams = []
          card_id = helpers.dom_id(@event, :card)

          if @event.published? && @event.published_at.present? && @event.published_at <= Time.current
            streams << turbo_stream.replace(
              card_id,
              partial: "public/events/event_card",
              locals: {
                event: @event,
                card_slot: params[:card_slot].presence || :grid_default,
                browse_state: browse_state
              }
            )
          else
            streams << turbo_stream.remove(card_id)
          end

          render turbo_stream: streams
        end
        format.html do
          redirect_back fallback_location: events_path(**browse_state.route_params(page: browse_state.page))
        end
      end
    end

    private

    def set_browse_state
      @browse_state = Public::Events::BrowseState.new(params)
    end

    def visible_events_relation(filter: Public::Events::BrowseState::FILTER_ALL, event_date: nil, query: nil)
      Public::VisibleEventsQuery.new(
        scope: index_events_relation,
        filter: filter,
        event_date: event_date,
        query: query
      ).call
    end

    def index_events_relation
      return published_future_events_relation unless authenticated?

      future_events_relation
    end

    def future_events_relation
      all_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .chronological
    end

    def published_future_events_relation
      published_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def assign_homepage_sections(current_relation)
      scoped_highlights = visible_events_relation(
        filter: Public::Events::BrowseState::FILTER_SKS,
        event_date: @browse_state.event_date,
        query: nil
      ).reorder(:start_at, :id)
      scoped_all = visible_events_relation(filter: Public::Events::BrowseState::FILTER_ALL, event_date: @browse_state.event_date, query: nil)
      scoped_reservix = scoped_all.where(primary_source: "reservix")

      @home_featured_events = scoped_highlights.to_a
      @home_featured_events = current_relation.reorder(:start_at, :id).to_a if @home_featured_events.empty?
      @home_highlight_events = scoped_reservix.limit(HOME_HIGHLIGHT_LIMIT).to_a
      @home_tagestipp_events = tagestipp_relation.to_a
      @selected_genre_tile = selected_genre_tile
      @selected_genre_events = selected_genre_events
    end

    def should_redirect_search_result?(relation)
      return false if @browse_state.query.blank?
      return false unless @browse_state.page == 1

      relation.limit(2).count == 1
    end

    def published_events_relation
      all_events_relation
        .published_live
    end

    def search_filter
      return Public::Events::BrowseState::FILTER_ALL if @browse_state.query.present?

      @browse_state.filter
    end

    def show_events_relation
      return published_events_relation unless authenticated?

      all_events_relation
    end

    def all_events_relation
      Event.includes(
        :genres,
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: :blob ]
      )
    end

    def tagestipp_relation
      visible_events_relation(
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: Time.zone.today,
        query: nil
      )
        .where.not(primary_source: "reservix")
        .reorder(Arel.sql(sks_first_order_sql), :start_at, :id)
    end

    def sks_first_order_sql
      quoted_ids = Event::SKS_PROMOTER_IDS.map { |id| ActiveRecord::Base.connection.quote(id) }.join(", ")
      "CASE WHEN events.promoter_id IN (#{quoted_ids}) THEN 0 ELSE 1 END"
    end

    def selected_genre_tile
      requested_slug = helpers.send(:public_event_genre_slug, params[:genre].to_s.strip)
      genre_tiles.find { |tile| tile[:slug] == requested_slug }
    end

    def selected_genre_events
      return [] unless selected_genre_tile.present?

      visible_events_relation(
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: nil,
        query: nil
      )
        .joins(:genres)
        .where(genres: { id: selected_genre_tile[:id] })
        .distinct
        .reorder(:start_at, :id)
        .to_a
    end

    def genre_tiles
      helpers.public_event_genre_tiles
    end

    def genre_panel_frame_request?
      turbo_frame_request? && request.headers["Turbo-Frame"] == "genre-events-panel"
    end

    def apply_status!(event, status)
      before_values = event.attributes.slice("status", "published_at", "published_by_id", "auto_published")

      event.status = status
      event.auto_published = false
      event.sync_publication_fields(user: current_user)
      event.save!
      after_values = event.attributes.slice("status", "published_at", "published_by_id", "auto_published")
      before_values != after_values
    end

    def render_not_found
      respond_to do |format|
      format.html do
          @browse_state ||= Public::Events::BrowseState.new(params)
          render "public/events/not_found", status: :not_found
        end
        format.any { head :not_found }
      end
    end
  end
end
