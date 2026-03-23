module Backend
  module Events
    class BulkUpdater
      def initialize(events:, action:, user:)
        @events = events
        @action = action.to_s
        @user = user
      end

      def call
        return assign_series! if action == "group_as_series"
        return remove_from_series! if action == "remove_from_series"

        processed = 0

        Event.transaction do
          events.find_each do |event|
            apply_action(event)
            Editorial::EventChangeLogger.log!(
              event: event,
              action: "bulk_#{action}",
              user: user
            )
            processed += 1
          end
        end

        processed
      end

      private

      attr_reader :action, :events, :user

      def apply_action(event)
        case action
        when "publish"
          event.publish_now!(user: user, auto_published: false)
        when "unpublish"
          event.unpublish!(status: "needs_review", auto_published: false)
        when "mark_complete"
          event.update!(status: "ready_for_publish")
        when "mark_incomplete"
          event.update!(status: "needs_review", auto_published: false)
        when "reject"
          event.update!(status: "rejected", auto_published: false)
        end
      end

      def assign_series!
        SeriesBulkAssignment.new(events:, user: user).assign!
      end

      def remove_from_series!
        SeriesBulkAssignment.new(events:, user: user).remove!
      end
    end
  end
end
