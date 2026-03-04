module Public
  class EventsController < ApplicationController
    allow_unauthenticated_access only: [ :index, :show ]

    PER_PAGE = 12
    FILTER_ALL = "all".freeze
    FILTER_SKS = "sks".freeze
    FILTER_VALUES = [ FILTER_ALL, FILTER_SKS ].freeze
    SKS_ORGANIZER_NAMES = [ "SKS E. Russ GmbH", "SKS Michael Russ GmbH" ].freeze
    SKS_PROMOTER_ID = "10135".freeze

    def index
      @page = [ params[:page].to_i, 1 ].max
      @public_filter = current_public_filter
      @public_event_date = current_public_event_date

      relation = visible_events_relation(filter: @public_filter, event_date: @public_event_date)
      @events = relation.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
      @next_page = @page + 1 if relation.offset(@page * PER_PAGE).limit(1).exists?

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @public_filter = current_public_filter
      @public_event_date = current_public_event_date
      @event = published_future_events_relation.find_by!(slug: params[:slug])
      @primary_offer = @event.primary_offer
    end

    def status
      @event = Event.find_by!(slug: params[:slug])
      desired_status = params[:status].to_s

      unless Event::STATUSES.include?(desired_status)
        redirect_back fallback_location: events_path(page: params[:page], filter: current_public_filter, event_date: current_public_event_date_param), alert: "Ungültiger Status."
        return
      end

      changed = apply_status!(@event, desired_status)
      Editorial::EventChangeLogger.log!(
        event: @event,
        action: "public_status_update",
        user: current_user,
        changed_fields: @event.saved_changes
      )

      message =
        if changed
          "Status für \"#{@event.artist_name}\" wurde auf #{helpers.public_event_status_label(@event.status)} gesetzt."
        else
          "Status für \"#{@event.artist_name}\" ist bereits #{helpers.public_event_status_label(@event.status)}."
        end

      respond_to do |format|
        format.html do
          redirect_back fallback_location: events_path(page: params[:page], filter: current_public_filter, event_date: current_public_event_date_param), notice: message
        end
        format.turbo_stream do
          flash.now[:notice] = message
          streams = [ turbo_stream.replace("flash-messages", partial: "layouts/flash_messages") ]
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
      end
    end

    private

    def visible_events_relation(filter: FILTER_ALL, event_date: nil)
      relation = published_future_events_relation
      relation = relation.where(start_at: event_date.beginning_of_day..event_date.end_of_day) if event_date.present?

      return relation unless filter == FILTER_SKS

      relation.where(
        "promoter_id = :promoter_id OR organizer_name IN (:organizer_names)",
        promoter_id: SKS_PROMOTER_ID,
        organizer_names: SKS_ORGANIZER_NAMES
      )
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

    def published_future_events_relation
      Event
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .includes(:genres, :event_offers, :import_event_images)
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
  end
end
