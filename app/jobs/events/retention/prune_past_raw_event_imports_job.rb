module Events
  module Retention
    class PrunePastRawEventImportsJob < ApplicationJob
      queue_as :default

      def perform
        Events::Retention::PrunePastRawEventImports.call
      end
    end
  end
end
