module Events
  module Publication
    class PublishScheduledEventsJob < ApplicationJob
      queue_as :default

      def perform
        Events::Publication::PublishScheduledEvents.call
      end
    end
  end
end
