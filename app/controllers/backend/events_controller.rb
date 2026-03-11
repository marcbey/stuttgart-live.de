module Backend
  class EventsController < BaseController
    EditorState = Data.define(:target_status, :sidebar_events, :sidebar_events_count, :target_event)

    before_action :set_event, only: [ :show, :update, :publish, :unpublish ]
    before_action :set_inbox_state
    before_action :set_next_event_enabled, only: [ :index, :show, :update, :publish, :unpublish ]
    before_action :load_all_genres, only: [ :index, :show, :new, :create, :update, :unpublish ]

    def index
      @latest_successful_merge_run = latest_successful_merge_run
      @filters = @inbox_state.filters
      @selected_merge_run_id = selected_merge_run_id_for_filters(@filters)
      @events = filtered_events_for_status(@filters[:status])
      @filtered_events_count = filtered_events_count(@events)
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
      next_event = next_event_fallback_for(@event, navigation_status: navigation_status)

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

        editor_state = editor_state_for(
          preferred_event: @event,
          navigation_status: navigation_status,
          fallback_event: next_event,
          prefer_fallback: @next_event_enabled
        )
        respond_with_editor_state(editor_state, notice: update_success_message)
      else
        flash.now[:alert] = "Event konnte nicht gespeichert werden."
        respond_to do |format|
          format.html { render :show, status: :unprocessable_entity }
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "event_editor",
                partial: "backend/events/editor_panel",
                locals: editor_panel_locals(event: @event, filter_status: navigation_status || @event.status)
              )
            ], status: :unprocessable_entity
          end
        end
      end
    end

    def publish
      @event.publish_now!(user: current_user, auto_published: false)
      Editorial::EventChangeLogger.log!(event: @event, action: "published", user: current_user)
      redirect_to backend_events_path(status: "published", event_id: @event.id), notice: "Event wurde veröffentlicht."
    end

    def unpublish
      navigation_status = @inbox_state.navigation_status
      next_event = next_event_fallback_for(@event, navigation_status: navigation_status)
      @event.unpublish!(status: "ready_for_publish", auto_published: false)
      Editorial::EventChangeLogger.log!(event: @event, action: "unpublished", user: current_user)
      editor_state = editor_state_for(
        preferred_event: @event,
        navigation_status: navigation_status,
        fallback_event: next_event,
        prefer_fallback: @next_event_enabled
      )

      respond_with_editor_state(editor_state, notice: "Event wurde depublisht.")
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

    def selected_event_from(events)
      if params[:event_id].present?
        return Event.includes(:import_event_images, event_images: [ file_attachment: :blob ]).find_by(id: params[:event_id])
      end

      events.first
    end

    def next_filtered_event_after(event_id, status:)
      return nil if status.blank?

      events = filtered_events_for_status(status).to_a
      index = events.index { |candidate| candidate.id == event_id }
      return nil if index.nil? || events.empty?
      return events.first if index >= events.length - 1

      events[index + 1]
    end

    def next_event_fallback_for(event, navigation_status:)
      next_event_status = navigation_status || event.status
      return nil unless @next_event_enabled

      next_filtered_event_after(event.id, status: next_event_status)
    end

    def selected_event_for_sidebar(sidebar_events, preferred_event:, fallback_event:, prefer_fallback: false)
      if prefer_fallback && fallback_event
        matched_fallback = sidebar_events.find { |candidate| candidate.id == fallback_event.id }
        return matched_fallback if matched_fallback.present?
      end

      sidebar_events.find { |candidate| candidate.id == preferred_event.id } ||
        (fallback_event && sidebar_events.find { |candidate| candidate.id == fallback_event.id }) ||
        sidebar_events.first
    end

    def filtered_events_for_status(status)
      filters = @inbox_state.filters_for(status: status)
      filters[:merge_run_id] = selected_merge_run_id_for_filters(filters) if filters[:merge_scope] == "last_merge"
      Editorial::EventsInboxQuery.new(params: filters).call
    end

    def filtered_events_count(relation)
      relation.except(:limit).count
    end

    def editor_state_for(preferred_event:, navigation_status:, fallback_event:, prefer_fallback: false)
      target_status = navigation_status || preferred_event.status
      sidebar_events = filtered_events_for_status(target_status)

      EditorState.new(
        target_status: target_status,
        sidebar_events: sidebar_events,
        sidebar_events_count: filtered_events_count(sidebar_events),
        target_event: selected_event_for_sidebar(
          sidebar_events,
          preferred_event: preferred_event,
          fallback_event: fallback_event,
          prefer_fallback: prefer_fallback
        )
      )
    end

    def status_filters
      @status_filters ||= Event::STATUSES.reject { |status| status == "imported" }
    end

    def latest_successful_merge_run
      ImportRun.where(source_type: "merge", status: "succeeded").order(finished_at: :desc, id: :desc).first
    end

    def selected_merge_run_id_for_filters(filters)
      return nil unless filters[:merge_scope] == "last_merge"

      @latest_successful_merge_run ||= latest_successful_merge_run
      @latest_successful_merge_run&.id
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

    def editor_panel_locals(event:, filter_status:)
      {
        event: event,
        all_genres: @all_genres,
        next_event_enabled: @next_event_enabled,
        filter_status: filter_status
      }
    end

    def respond_with_editor_state(editor_state, notice:)
      respond_to do |format|
        format.html do
          redirect_to backend_events_path(status: editor_state.target_status, event_id: editor_state.target_event&.id), notice: notice
        end
        format.turbo_stream do
          flash.now[:notice] = notice
          render_editor_state_turbo_stream(editor_state: editor_state)
        end
      end
    end

    def render_editor_state_turbo_stream(editor_state:)
      render turbo_stream: [
        turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
        turbo_stream.replace(
          "event_topbar_context",
          partial: "backend/events/topbar_context",
          locals: { event: editor_state.target_event }
        ),
        turbo_stream.replace(
          "event_topbar_editor_actions",
          partial: "backend/events/topbar_editor_actions",
          locals: {
            event: editor_state.target_event,
            next_event_enabled: @next_event_enabled,
            filter_status: editor_state.target_status
          }
        ),
        turbo_stream.replace(
          "events_list",
          partial: "backend/events/events_list",
          locals: {
            events: editor_state.sidebar_events,
            selected_event: editor_state.target_event,
            status: editor_state.target_status,
            merge_run_id: selected_merge_run_id_for_filters(@inbox_state.filters_for(status: editor_state.target_status)),
            filtered_events_count: editor_state.sidebar_events_count
          }
        ),
        turbo_stream.replace(
          "event_editor",
          partial: (editor_state.target_event.present? ? "backend/events/editor_panel" : "backend/events/empty_editor"),
          locals: (
            if editor_state.target_event.present?
              editor_panel_locals(event: editor_state.target_event, filter_status: editor_state.target_status)
            else
              {}
            end
          )
        )
      ]
    end
  end
end
