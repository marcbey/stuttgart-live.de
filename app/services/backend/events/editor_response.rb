module Backend
  module Events
    class EditorResponse
      def initialize(controller:, all_genres:, all_presenters:, next_event_enabled:)
        @controller = controller
        @all_genres = all_genres
        @all_presenters = all_presenters
        @next_event_enabled = next_event_enabled
      end

      def success(editor_state:, notice:, active_editor_tab: "event")
        controller.respond_to do |format|
          format.html do
            controller.redirect_to(
              controller.backend_events_path(status: editor_state.target_status, event_id: editor_state.target_event&.id),
              notice: notice
            )
          end
          format.turbo_stream do
            controller.flash.now[:notice] = notice
            controller.render turbo_stream: success_streams(editor_state:, active_editor_tab:)
          end
        end
      end

      def validation_error(event:, filter_status:, active_editor_tab: "event")
        controller.flash.now[:alert] = "Event konnte nicht gespeichert werden."

        controller.respond_to do |format|
          format.html do
            controller.instance_variable_set(:@active_editor_tab, active_editor_tab)
            controller.render :show, status: :unprocessable_entity
          end
          format.turbo_stream do
            controller.render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace(
                "event_editor",
                partial: "backend/events/editor_frame",
                locals: editor_frame_locals(event: event, filter_status: filter_status, active_editor_tab: active_editor_tab)
              )
            ], status: :unprocessable_entity
          end
        end
      end

      private

      attr_reader :all_genres, :all_presenters, :controller, :next_event_enabled

      def success_streams(editor_state:, active_editor_tab:)
        [
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
              next_event_enabled: next_event_enabled,
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
              merge_run_id: editor_state.merge_run_id,
              filtered_events_count: editor_state.sidebar_events_count
            }
          ),
          turbo_stream.replace(
            "event_editor",
            partial: "backend/events/editor_frame",
            locals: editor_frame_locals(
              event: editor_state.target_event,
              filter_status: editor_state.target_status,
              active_editor_tab: active_editor_tab
            )
          )
        ]
      end

      def turbo_stream
        controller.send(:turbo_stream)
      end

      def editor_frame_locals(event:, filter_status:, active_editor_tab: "event")
        {
          event: event,
          all_genres: all_genres,
          all_presenters: all_presenters,
          next_event_enabled: next_event_enabled,
          filter_status: filter_status,
          active_editor_tab: active_editor_tab,
          manual_ticket_url: controller.instance_variable_get(:@manual_ticket_url),
          manual_ticket_sold_out: controller.instance_variable_get(:@manual_ticket_sold_out)
        }
      end
    end
  end
end
