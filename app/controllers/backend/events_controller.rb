module Backend
  class EventsController < BaseController
    SESSION_FILTERS_KEY = "backend_events_inbox_filters".freeze
    SESSION_NEXT_EVENT_KEY = "backend_events_next_event_enabled".freeze

    before_action :set_event, only: [ :show, :update, :publish, :unpublish ]
    before_action :set_next_event_enabled, only: [ :index, :show, :update ]

    def index
      @filters = session_filters_for_index.merge(status: current_status)
      @events = filtered_events_for_status(@filters[:status])
      @status_counts = Event.group(:status).count
      @all_genres = Genre.order(:name)
      @selected_event = selected_event_from(@events)
    end

    def apply_filters
      persist_session_filters!(
        clear: clear_filters_requested?,
        query: params[:query],
        starts_after: params[:starts_after],
        starts_before: params[:starts_before]
      )

      redirect_to backend_events_path(status: current_status)
    end

    def next_event_preference
      persist_next_event_preference!(params[:enabled])
      head :ok
    end

    def show
      @all_genres = Genre.order(:name)
      @filter_status = inbox_status_for_navigation
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
      persist_next_event_preference!(params[:next_event_enabled]) if params.key?(:next_event_enabled)
      navigation_status = inbox_status_for_navigation
      next_event = @next_event_enabled ? next_filtered_event_after(@event.id, status: navigation_status) : nil

      @event.assign_attributes(event_params)
      @event.status = "published" if save_and_publish_requested?
      set_publishing_fields!(@event)

      if @event.save
        refresh_completeness!(@event)
        Editorial::EventChangeLogger.log!(
          event: @event,
          action: "updated",
          user: current_user,
          changed_fields: @event.saved_changes
        )

        target_event = next_event || @event
        target_status = navigation_status || @event.status
        sidebar_events = filtered_events_for_status(target_status)

        respond_to do |format|
          format.html { redirect_to backend_events_path(status: target_status, event_id: target_event.id), notice: update_success_message }
          format.turbo_stream do
            flash.now[:notice] = update_success_message
            render turbo_stream: [
              turbo_stream.replace("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "events_list",
                partial: "backend/events/events_list",
                locals: { events: sidebar_events, selected_event: target_event, status: target_status }
              ),
              turbo_stream.replace(
                "event_editor",
                partial: "backend/events/editor_panel",
                locals: {
                  event: target_event,
                  all_genres: @all_genres,
                  next_event_enabled: @next_event_enabled,
                  filter_status: target_status
                }
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
                locals: {
                  event: @event,
                  all_genres: @all_genres,
                  next_event_enabled: @next_event_enabled,
                  filter_status: navigation_status
                }
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

      if event_ids.blank?
        redirect_to backend_events_path(status: current_status), alert: "Bitte mindestens ein Event auswählen."
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
          end

          Editorial::EventChangeLogger.log!(
            event: event,
            action: "bulk_#{action}",
            user: current_user
          )
          processed += 1
        end
      end

      redirect_to backend_events_path(status: current_status), notice: "Bulk-Aktion abgeschlossen (#{processed} Events)."
    end

    def sync_imported_events
      Merging::SyncImportedEventsJob.perform_later
      redirect_to backend_events_path(status: current_status), notice: "Merge-Sync wurde gestartet."
    end

    private

    def set_event
      @event = Event.find(params[:id])
    end

    def set_next_event_enabled
      @next_event_enabled = next_event_enabled_preference
    end

    def current_status
      value = params[:status].to_s
      return value if Event::STATUSES.include?(value)

      "needs_review"
    end

    def clear_filters_requested?
      ActiveModel::Type::Boolean.new.cast(params[:clear_filters])
    end

    def session_filters_for_index
      stored = session[SESSION_FILTERS_KEY]
      normalized = stored.is_a?(Hash) ? stored.stringify_keys : {}

      {
        query: normalized["query"].to_s.strip.presence,
        starts_after: normalized["starts_after"].to_s.strip.presence,
        starts_before: normalized["starts_before"].to_s.strip.presence
      }
    end

    def persist_session_filters!(clear:, query:, starts_after:, starts_before:)
      if clear
        session.delete(SESSION_FILTERS_KEY)
        return
      end

      session[SESSION_FILTERS_KEY] = {
        "query" => query.to_s.strip.presence,
        "starts_after" => starts_after.to_s.strip.presence,
        "starts_before" => starts_before.to_s.strip.presence
      }
    end

    def next_event_enabled_preference
      value = session[SESSION_NEXT_EVENT_KEY]
      return true if value.nil?

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def persist_next_event_preference!(value)
      normalized = ActiveModel::Type::Boolean.new.cast(value)
      session[SESSION_NEXT_EVENT_KEY] = normalized
      @next_event_enabled = normalized
    end

    def selected_event_from(events)
      return Event.find_by(id: params[:event_id]) if params[:event_id].present?

      events.first
    end

    def inbox_status_for_navigation
      value = params[:inbox_status].to_s
      return value if Event::STATUSES.include?(value)

      nil
    end

    def next_filtered_event_after(event_id, status:)
      return nil if status.blank?

      events = filtered_events_for_status(status).to_a
      index = events.index { |candidate| candidate.id == event_id }
      return nil if index.nil? || events.empty?
      return events.first if index >= events.length - 1

      events[index + 1]
    end

    def filtered_events_for_status(status)
      filters = session_filters_for_index.merge(status: status)
      Editorial::EventsInboxQuery.new(params: filters).call
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
