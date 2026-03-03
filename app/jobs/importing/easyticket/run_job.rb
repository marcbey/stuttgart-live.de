module Importing
  module Easyticket
    class RunJob < ApplicationJob
      queue_as :imports_easyticket

      def perform(import_source_id = nil)
        source =
          if import_source_id.present?
            ImportSource.find(import_source_id)
          else
            ImportSource.ensure_easyticket_source!
          end

        run = Importing::Easyticket::Importer.new(import_source: source).call
        Merging::SyncImportedEventsJob.perform_later if run.status == "succeeded"
      end
    end
  end
end
