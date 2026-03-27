module Events
  module Retention
    class PruneStaleUnpublishedEventsJob < ApplicationJob
      queue_as :default

      def perform
        Events::Retention::PruneStaleUnpublishedEvents.call
      end
    end
  end
end
