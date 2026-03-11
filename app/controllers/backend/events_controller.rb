module Backend
  class EventsController < BaseController
    before_action :set_event, only: [ :show, :update, :publish, :unpublish ]
    before_action :set_inbox_state
    before_action :set_next_event_enabled, only: [ :index, :show, :update, :publish, :unpublish ]
    before_action :load_all_genres, only: [ :index, :show, :new, :create, :update, :unpublish ]

    def index
      @latest_successful_merge_run = latest_successful_merge_run
      @editor_state_builder = build_editor_state_builder
      @filters = @inbox_state.filters
      @selected_merge_run_id = @editor_state_builder.selected_merge_run_id_for_status(@filters[:status])
      @events = @editor_state_builder.events_for_status(@filters[:status])
      @filtered_events_count = @editor_state_builder.filtered_events_count(@events)
      @status_filters = status_filters
      @selected_event = selected_event_from(@events)
    end

    def apply_filters
      @inbox_state.persist_filters!
      redirect_to backend_events_path(status: @inbox_state.current_status)
    end

    def next_event_preference
      @next_event_enabled = @inbox_state.persist_next_event_preference!(params[:enabled])
      head :ok
    end

    def show
      @filter_status = @inbox_state.navigation_status || params[:status].to_s.presence_in(status_filters)
    end

    def new
      @event = Event.new(start_at: Time.current.change(hour: 20, min: 0), status: "needs_review")
    end

    def create
      @event = Event.new(event_params)

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
      @next_event_enabled = @inbox_state.persist_next_event_preference!(params[:next_event_enabled]) if params.key?(:next_event_enabled)
      navigation_status = @inbox_state.navigation_status

      @event.assign_attributes(event_params)
      @event.status = "published" if save_and_publish_requested?
      set_publishing_fields!(@event)

      if @event.save
        assign_genres!(@event) if params[:event].respond_to?(:key?) && params[:event].key?(:genre_ids)
        refresh_completeness!(@event)
        Editorial::EventChangeLogger.log!(
          event: @event,
          action: "updated",
          user: current_user,
          changed_fields: @event.saved_changes
        )

        editor_response.success(
          editor_state: build_editor_state_builder.build(preferred_event: @event, navigation_status: navigation_status),
          notice: update_success_message
        )
      else
        editor_response.validation_error(event: @event, filter_status: navigation_status || @event.status)
      end
    end

    def publish
      @event.publish_now!(user: current_user, auto_published: false)
      Editorial::EventChangeLogger.log!(event: @event, action: "published", user: current_user)
      redirect_to backend_events_path(status: "published", event_id: @event.id), notice: "Event wurde veröffentlicht."
    end

    def unpublish
      navigation_status = @inbox_state.navigation_status
      @event.unpublish!(status: "ready_for_publish", auto_published: false)
      Editorial::EventChangeLogger.log!(event: @event, action: "unpublished", user: current_user)
      editor_response.success(
        editor_state: build_editor_state_builder.build(
          preferred_event: @event,
          navigation_status: navigation_status
        ),
        notice: "Event wurde depublisht."
      )
    end

    def bulk
      event_ids = Array(params[:event_ids]).map(&:to_i).uniq
      action = params[:bulk_action].to_s

      if event_ids.blank?
        redirect_to backend_events_path(status: @inbox_state.current_status), alert: "Bitte mindestens ein Event auswählen."
        return
      end

      events = Event.where(id: event_ids)
      processed = Backend::Events::BulkUpdater.new(events: events, action: action, user: current_user).call

      redirect_to backend_events_path(status: @inbox_state.current_status), notice: "Bulk-Aktion abgeschlossen (#{processed} Events)."
    end

    private

    def set_inbox_state
      @inbox_state = Backend::Events::InboxState.new(
        params: params,
        session: session,
        status_filters: status_filters
      )
    end

    def set_event
      @event = Event.includes(:import_event_images, event_images: [ file_attachment: :blob ]).find(params[:id])
    end

    def set_next_event_enabled
      @next_event_enabled = @inbox_state.next_event_enabled
    end

    def load_all_genres
      @all_genres = Genre.order(:name)
    end

    def build_editor_state_builder
      Backend::Events::EditorStateBuilder.new(
        inbox_state: @inbox_state,
        latest_successful_merge_run: @latest_successful_merge_run || latest_successful_merge_run,
        next_event_enabled: @next_event_enabled
      )
    end

    def editor_response
      @editor_response ||= Backend::Events::EditorResponse.new(
        controller: self,
        all_genres: @all_genres,
        next_event_enabled: @next_event_enabled
      )
    end

    def selected_event_from(events)
      if params[:event_id].present?
        return Event.includes(:import_event_images, event_images: [ file_attachment: :blob ]).find_by(id: params[:event_id])
      end

      events.first
    end

    def status_filters
      @status_filters ||= Event::STATUSES.reject { |status| status == "imported" }
    end

    def latest_successful_merge_run
      ImportRun.where(source_type: "merge", status: "succeeded").order(finished_at: :desc, id: :desc).first
    end

    def event_params
      params.require(:event).permit(
        :title,
        :artist_name,
        :start_at,
        :doors_at,
        :venue,
        :city,
        :event_info,
        :organizer_notes,
        :show_organizer_notes,
        :badge_text,
        :homepage_url,
        :instagram_url,
        :facebook_url,
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
      event.sync_publication_fields(user: current_user)
    end

    def save_and_publish_requested?
      ActiveModel::Type::Boolean.new.cast(params[:save_and_publish])
    end

    def update_success_message
      save_and_publish_requested? ? "Event wurde gespeichert und publiziert." : "Event wurde gespeichert."
    end
  end
end
