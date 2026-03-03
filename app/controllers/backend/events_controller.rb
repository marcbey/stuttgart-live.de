module Backend
  class EventsController < BaseController
    before_action :set_event, only: [ :show, :update, :publish, :unpublish ]

    def index
      @filters = filter_params.to_h.symbolize_keys
      @filters[:status] = "needs_review" if @filters[:status].blank?
      @events = Editorial::EventsInboxQuery.new(params: @filters).call
      @status_counts = Event.group(:status).count
      @all_genres = Genre.order(:name)
      @selected_event = selected_event_from(@events)
    end

    def show
      @all_genres = Genre.order(:name)
    end

    def new
      @event = Event.new(start_at: Time.current.change(hour: 20, min: 0), status: "needs_review")
      @all_genres = Genre.order(:name)
    end

    def create
      @event = Event.new(event_params)
      @all_genres = Genre.order(:name)

      set_publishing_fields!(@event)

      if @event.save
        assign_genres!(@event)
        refresh_completeness!(@event)
        Editorial::EventChangeLogger.log!(
          event: @event,
          action: "created",
          user: current_user,
          changed_fields: @event.saved_changes
        )

        redirect_to backend_events_path(status: @event.status, event_id: @event.id), notice: "Event wurde erstellt."
      else
        flash.now[:alert] = "Event konnte nicht erstellt werden."
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @all_genres = Genre.order(:name)

      @event.assign_attributes(event_params)
      @event.status = "published" if save_and_publish_requested?
      set_publishing_fields!(@event)

      if @event.save
        assign_genres!(@event)
        refresh_completeness!(@event)
        Editorial::EventChangeLogger.log!(
          event: @event,
          action: "updated",
          user: current_user,
          changed_fields: @event.saved_changes
        )

        respond_to do |format|
          format.html { redirect_to backend_events_path(status: @event.status, event_id: @event.id), notice: update_success_message }
          format.turbo_stream do
            flash.now[:notice] = update_success_message
            render turbo_stream: [
              turbo_stream.replace("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "event_editor",
                partial: "backend/events/editor_panel",
                locals: { event: @event, all_genres: @all_genres }
              )
            ]
          end
        end
      else
        flash.now[:alert] = "Event konnte nicht gespeichert werden."
        respond_to do |format|
          format.html { render :show, status: :unprocessable_entity }
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "event_editor",
                partial: "backend/events/editor_panel",
                locals: { event: @event, all_genres: @all_genres }
              )
            ], status: :unprocessable_entity
          end
        end
      end
    end

    def publish
      @event.update!(status: "published", published_at: Time.current, published_by: current_user, auto_published: false)
      Editorial::EventChangeLogger.log!(event: @event, action: "published", user: current_user)
      redirect_to backend_events_path(status: "published", event_id: @event.id), notice: "Event wurde veröffentlicht."
    end

    def unpublish
      @event.update!(status: "needs_review", published_at: nil, published_by: nil, auto_published: false)
      Editorial::EventChangeLogger.log!(event: @event, action: "unpublished", user: current_user)
      redirect_to backend_events_path(status: "needs_review", event_id: @event.id), notice: "Event wurde depublisht."
    end

    def bulk
      event_ids = Array(params[:event_ids]).map(&:to_i).uniq
      action = params[:bulk_action].to_s
      genre_id = params[:genre_id].presence

      if event_ids.blank?
        redirect_to backend_events_path(filter_params), alert: "Bitte mindestens ein Event auswählen."
        return
      end

      events = Event.where(id: event_ids)
      processed = 0

      Event.transaction do
        events.find_each do |event|
          case action
          when "publish"
            event.update!(status: "published", published_at: Time.current, published_by: current_user, auto_published: false)
          when "unpublish"
            event.update!(status: "needs_review", published_at: nil, published_by: nil, auto_published: false)
          when "mark_complete"
            event.update!(status: "ready_for_publish")
          when "mark_incomplete"
            event.update!(status: "needs_review", auto_published: false)
          when "reject"
            event.update!(status: "rejected", auto_published: false)
          when "set_genre"
            next unless genre_id

            genre = Genre.find_by(id: genre_id)
            next unless genre

            event.genres = [ genre ]
            refresh_completeness!(event)
          end

          Editorial::EventChangeLogger.log!(
            event: event,
            action: "bulk_#{action}",
            user: current_user,
            metadata: { genre_id: genre_id }
          )
          processed += 1
        end
      end

      redirect_to backend_events_path(filter_params), notice: "Bulk-Aktion abgeschlossen (#{processed} Events)."
    end

    def sync_imported_events
      Merging::SyncImportedEventsJob.perform_later
      redirect_to backend_events_path(status: filter_params[:status]), notice: "Merge-Sync wurde gestartet."
    end

    private

    def set_event
      @event = Event.find(params[:id])
    end

    def filter_params
      params.permit(:status, :query, :starts_after, :starts_before)
    end

    def selected_event_from(events)
      return Event.find_by(id: params[:event_id]) if params[:event_id].present?

      events.first
    end

    def event_params
      params.require(:event).permit(
        :title,
        :artist_name,
        :start_at,
        :venue,
        :city,
        :event_info,
        :badge_text,
        :image_url,
        :youtube_url,
        :status,
        :editor_notes
      )
    end

    def genre_ids_from_params
      Array(params.dig(:event, :genre_ids)).reject(&:blank?).map(&:to_i)
    end

    def assign_genres!(event)
      return unless params[:event].is_a?(ActionController::Parameters) || params[:event].is_a?(Hash)

      ids = genre_ids_from_params
      event.genres = Genre.where(id: ids)
    end

    def refresh_completeness!(event)
      result = Editorial::EventCompletenessChecker.new(event: event).call
      event.update!(
        completeness_score: result.score,
        completeness_flags: result.flags,
        status: normalized_status_for(event, result)
      )
    end

    def normalized_status_for(event, completeness_result)
      return event.status if event.published? || event.status == "rejected"

      completeness_result.ready_for_publish? ? "ready_for_publish" : "needs_review"
    end

    def set_publishing_fields!(event)
      if event.status == "published"
        event.published_at ||= Time.current
        event.published_by ||= current_user
      elsif event.status != "published"
        event.published_at = nil
        event.published_by = nil
      end
    end

    def save_and_publish_requested?
      ActiveModel::Type::Boolean.new.cast(params[:save_and_publish])
    end

    def update_success_message
      save_and_publish_requested? ? "Event wurde gespeichert und publiziert." : "Event wurde gespeichert."
    end
  end
end
