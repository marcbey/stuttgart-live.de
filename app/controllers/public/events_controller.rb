module Public
  class EventsController < ApplicationController
    allow_unauthenticated_access

    PER_PAGE = 12

    def index
      @page = [ params[:page].to_i, 1 ].max

      relation = Event.published_live.includes(:genres, :event_offers)
      @events = relation.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
      @next_page = @page + 1 if relation.offset(@page * PER_PAGE).limit(1).exists?

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @event = Event.published_live.includes(:genres, :event_offers).find_by!(slug: params[:slug])
      @primary_offer = @event.primary_offer
    end
  end
end
