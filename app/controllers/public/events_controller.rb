module Public
  class EventsController < ApplicationController
    allow_unauthenticated_access only: [ :index, :show ]

    PER_PAGE = 12

    def index
      @page = [ params[:page].to_i, 1 ].max

      relation = Event.published_live.includes(:genres, :event_offers, :import_event_images)
      @events = relation.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
      @next_page = @page + 1 if relation.offset(@page * PER_PAGE).limit(1).exists?

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @event = Event.published_live.includes(:genres, :event_offers, :import_event_images).find_by!(slug: params[:slug])
      @primary_offer = @event.primary_offer
    end

    def status
      @event = Event.find_by!(slug: params[:slug])
      desired_status = params[:status].to_s

      unless Event::STATUSES.include?(desired_status)
        redirect_back fallback_location: events_path(page: params[:page]), alert: "Ungültiger Status."
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
          redirect_back fallback_location: events_path(page: params[:page]), notice: message
        end
        format.turbo_stream do
          flash.now[:notice] = message
          streams = [ turbo_stream.replace("flash-messages", partial: "layouts/flash_messages") ]
          card_id = helpers.dom_id(@event, :card)

          if @event.published? && @event.published_at.present? && @event.published_at <= Time.current
            streams << turbo_stream.replace(
              card_id,
              partial: "public/events/event_card",
              locals: { event: @event, card_slot: params[:card_slot].presence || :grid_default }
            )
          else
            streams << turbo_stream.remove(card_id)
          end

          render turbo_stream: streams
        end
      end
    end

    private

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
