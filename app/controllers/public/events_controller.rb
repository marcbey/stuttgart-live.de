module Public
  class EventsController < ApplicationController
    allow_unauthenticated_access only: [ :index, :show ]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    PER_PAGE = 12
    FILTER_ALL = "all".freeze
    FILTER_SKS = "sks".freeze
    FILTER_VALUES = [ FILTER_ALL, FILTER_SKS ].freeze
    SKS_PROMOTER_IDS = %w[10135 382].freeze
    VIEW_GRID = "grid".freeze
    VIEW_LIST = "list".freeze
    VIEW_VALUES = [ VIEW_GRID, VIEW_LIST ].freeze

    def index
      @page = [ params[:page].to_i, 1 ].max
      @public_filter = current_public_filter
      @public_view = current_public_view
      @public_event_date = current_public_event_date
      @public_query = current_public_query

      relation = visible_events_relation(filter: @public_filter, event_date: @public_event_date, query: @public_query)
      @events = relation.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
      @next_page = @page + 1 if relation.offset(@page * PER_PAGE).limit(1).exists?
      assign_homepage_sections(relation) if @page == 1 && @public_view == VIEW_GRID

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @public_filter = current_public_filter
      @public_view = current_public_view
      @public_event_date = current_public_event_date
      @public_query = current_public_query
      @event = show_events_relation.find_by!(slug: params[:slug])
      @primary_offer = @event.preferred_ticket_offer
    end

    def status
      @event = Event.find_by!(slug: params[:slug])
      desired_status = params[:status].to_s

      unless Event::STATUSES.include?(desired_status)
        redirect_back fallback_location: events_path(page: params[:page], filter: current_public_filter, event_date: current_public_event_date_param)
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
                public_filter: current_public_filter,
                public_event_date: current_public_event_date_param
              }
            )
          else
            streams << turbo_stream.remove(card_id)
          end

          render turbo_stream: streams
        end
        format.html do
          redirect_back fallback_location: events_path(page: params[:page], filter: current_public_filter, view: current_public_view_param, event_date: current_public_event_date_param)
        end
      end
    end

    private

    def visible_events_relation(filter: FILTER_ALL, event_date: nil, query: nil)
      relation = published_future_events_relation
      relation = relation.where(start_at: event_date.beginning_of_day..event_date.end_of_day) if event_date.present?
      relation = apply_public_query(relation, query) if query.present?

      return relation unless filter == FILTER_SKS

      relation.where(promoter_id: SKS_PROMOTER_IDS)
    end

    def current_public_filter
      return @current_public_filter if defined?(@current_public_filter)

      value = params[:filter].to_s
      @current_public_filter =
        if FILTER_VALUES.include?(value)
          value
        else
          FILTER_SKS
        end
    end

    def current_public_event_date
      return @current_public_event_date if defined?(@current_public_event_date)

      value = params[:event_date].to_s.strip
      @current_public_event_date =
        begin
          value.present? ? Date.iso8601(value) : nil
        rescue ArgumentError
          nil
        end
    end

    def current_public_event_date_param
      current_public_event_date&.iso8601
    end

    def current_public_query
      return @current_public_query if defined?(@current_public_query)

      @current_public_query = params[:q].to_s.strip.presence
    end

    def current_public_view_param
      current_public_view == VIEW_LIST ? VIEW_LIST : nil
    end

    def current_public_view
      return @current_public_view if defined?(@current_public_view)

      value = params[:view].to_s
      @current_public_view =
        if VIEW_VALUES.include?(value)
          value
        else
          VIEW_GRID
        end
    end

    def published_future_events_relation
      published_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def assign_homepage_sections(current_relation)
      scoped_highlights = visible_events_relation(filter: FILTER_SKS, event_date: @public_event_date, query: @public_query)

      @home_featured_events = scoped_highlights.to_a
      @home_featured_events = current_relation.limit(PER_PAGE).to_a if @home_featured_events.empty?
      @home_highlight_events = scoped_highlights.limit(10).to_a
      @home_tagestipp_events = current_relation.offset(6).limit(10).to_a
      @home_tagestipp_events = current_relation.limit(10).to_a if @home_tagestipp_events.empty?
    end

    def apply_public_query(relation, query)
      token = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

      relation.where(
        "events.artist_name ILIKE :token OR events.title ILIKE :token OR events.venue ILIKE :token OR events.city ILIKE :token",
        token: token
      )
    end

    def published_events_relation
      Event
        .published_live
        .includes(
          :genres,
          :event_offers,
          :import_event_images,
          event_images: [ file_attachment: :blob ]
        )
    end

    def show_events_relation
      return published_events_relation unless authenticated?

      Event
        .includes(
          :genres,
          :event_offers,
          :import_event_images,
          event_images: [ file_attachment: :blob ]
        )
    end

    def apply_status!(event, status)
      before_values = event.attributes.slice("status", "published_at", "published_by_id", "auto_published")

      event.status = status
      event.auto_published = false

      if status == "published"
        event.published_at ||= Time.current
        event.published_by ||= current_user
      else
        event.published_at = nil
        event.published_by = nil
      end

      event.save!
      after_values = event.attributes.slice("status", "published_at", "published_by_id", "auto_published")
      before_values != after_values
    end

    def render_not_found
      respond_to do |format|
        format.html do
          @public_filter = current_public_filter
          @public_view = current_public_view
          @public_event_date = current_public_event_date
          @public_query = current_public_query
          render "public/events/not_found", status: :not_found
        end
        format.any { head :not_found }
      end
    end
  end
end
