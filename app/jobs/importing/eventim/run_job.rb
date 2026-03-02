module Importing
  module Eventim
    class RunJob < ApplicationJob
      queue_as :imports_eventim

      def perform(import_source_id = nil)
        source =
          if import_source_id.present?
            ImportSource.find(import_source_id)
          else
            ImportSource.ensure_eventim_source!
          end

        Importing::Eventim::Importer.new(import_source: source).call
      end
    end
  end
end
