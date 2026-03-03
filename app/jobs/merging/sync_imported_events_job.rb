module Merging
  class SyncImportedEventsJob < ApplicationJob
    queue_as :default

    def perform
      Merging::SyncFromImports.new.call
    end
  end
end
