module Importing
  class DailyRunJob < ApplicationJob
    queue_as :default

    def perform
      ImportSource.ensure_supported_sources!

      ImportSource.where(source_type: %w[easyticket eventim reservix], active: true).find_each do |source|
        case source.source_type
        when "easyticket"
          Importing::Easyticket::RunJob.perform_later(source.id)
        when "eventim"
          Importing::Eventim::RunJob.perform_later(source.id)
        when "reservix"
          Importing::Reservix::RunJob.perform_later(source.id)
        end
      end
    end
  end
end
