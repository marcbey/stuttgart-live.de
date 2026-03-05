module Merging
  class SyncImportedEventsJob < ApplicationJob
    queue_as :default

    def perform
      run = nil
      run = start_run!
      broadcast_runs_update!

      result = Merging::SyncFromImports.new(merge_run_id: run.id).call

      run.update!(
        status: "succeeded",
        finished_at: Time.current,
        fetched_count: result.import_records_count,
        filtered_count: 0,
        imported_count: result.events_created_count + result.events_updated_count,
        upserted_count: result.offers_upserted_count,
        failed_count: 0,
        metadata: {
          "import_records_count" => result.import_records_count,
          "groups_count" => result.groups_count,
          "events_created_count" => result.events_created_count,
          "events_updated_count" => result.events_updated_count,
          "offers_upserted_count" => result.offers_upserted_count
        }
      )
    rescue StandardError => e
      run&.update!(
        status: "failed",
        finished_at: Time.current,
        error_message: e.message
      )
      create_import_run_error!(run: run, error: e)
      raise
    ensure
      broadcast_runs_update!
    end

    private

    def start_run!
      ImportRun.create!(
        import_source: run_source,
        source_type: "merge",
        status: "running",
        started_at: Time.current
      )
    end

    def run_source
      ImportSource.find_by(source_type: "eventim") ||
        ImportSource.find_by(source_type: "easyticket") ||
        ImportSource.ensure_eventim_source!
    end

    def broadcast_runs_update!
      Backend::ImportRunsBroadcaster.broadcast!
    end

    def create_import_run_error!(run:, error:)
      return unless run&.persisted?

      run.import_run_errors.create!(
        source_type: "merge",
        error_class: error.class.to_s,
        message: error.message.to_s.presence || error.class.to_s,
        payload: {}
      )
    rescue StandardError
      nil
    end
  end
end
