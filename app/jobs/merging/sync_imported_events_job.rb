module Merging
  class SyncImportedEventsJob < ApplicationJob
    queue_as :default
    PROGRESS_FLUSH_EVERY_N_GROUPS = 25
    PROGRESS_FLUSH_AFTER = 2.seconds

    def perform(last_run_at: nil)
      run = nil
      normalized_last_run_at = normalize_last_run_at(last_run_at)
      run = start_run!(last_run_at: normalized_last_run_at)
      broadcast_runs_update!

      progress_state = {
        last_flushed_at: Time.current,
        last_flushed_processed_groups_count: nil
      }

      result = Merging::SyncFromImports.new(
        merge_run_id: run.id,
        last_run_at: normalized_last_run_at,
        progress_callback: ->(progress) { persist_progress!(run, progress, progress_state) }
      ).call

      run.update!(
        status: "succeeded",
        finished_at: Time.current,
        fetched_count: result.import_records_count,
        filtered_count: 0,
        imported_count: result.events_created_count + result.events_updated_count,
        upserted_count: result.offers_upserted_count,
        failed_count: 0,
        metadata: current_run_metadata(run).merge(
          "import_records_count" => result.import_records_count,
          "groups_count" => result.groups_count,
          "events_created_count" => result.events_created_count,
          "events_updated_count" => result.events_updated_count,
          "duplicate_matches_count" => result.duplicate_matches_count,
          "offers_upserted_count" => result.offers_upserted_count
        )
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

    def start_run!(last_run_at:)
      ImportRun.create!(
        import_source: run_source,
        source_type: "merge",
        status: "running",
        started_at: Time.current,
        metadata: merge_run_metadata(last_run_at:)
      )
    end

    def run_source
      ImportSource.find_by(source_type: "eventim") ||
        ImportSource.find_by(source_type: "easyticket") ||
        ImportSource.ensure_eventim_source!
    end

    def merge_run_metadata(last_run_at:)
      metadata = {}
      metadata["last_run_at"] = last_run_at.iso8601 if last_run_at.present?
      metadata
    end

    def persist_progress!(run, progress, progress_state)
      progress = progress.deep_stringify_keys
      processed_groups_count = Integer(progress["processed_groups_count"], exception: false)
      return unless should_flush_progress?(processed_groups_count, progress_state)

      merged_metadata = current_run_metadata(run).merge(progress.slice(
        "import_records_count",
        "groups_count",
        "events_created_count",
        "events_updated_count",
        "duplicate_matches_count",
        "offers_upserted_count",
        "processed_groups_count"
      ))

      events_created_count = Integer(merged_metadata["events_created_count"], exception: false) || 0
      events_updated_count = Integer(merged_metadata["events_updated_count"], exception: false) || 0
      offers_upserted_count = Integer(merged_metadata["offers_upserted_count"], exception: false) || 0
      import_records_count = Integer(merged_metadata["import_records_count"], exception: false) || 0

      run.update_columns(
        fetched_count: import_records_count,
        imported_count: events_created_count + events_updated_count,
        upserted_count: offers_upserted_count,
        metadata: merged_metadata,
        updated_at: Time.current
      )
      progress_state[:last_flushed_at] = Time.current
      progress_state[:last_flushed_processed_groups_count] = processed_groups_count
      broadcast_runs_update!
    end

    def should_flush_progress?(processed_groups_count, progress_state)
      last_flushed_processed_groups_count = progress_state[:last_flushed_processed_groups_count]
      return true if last_flushed_processed_groups_count.nil?

      progressed_groups = processed_groups_count.to_i - last_flushed_processed_groups_count.to_i
      return true if progressed_groups >= PROGRESS_FLUSH_EVERY_N_GROUPS

      (Time.current - progress_state[:last_flushed_at]) >= PROGRESS_FLUSH_AFTER
    end

    def current_run_metadata(run)
      return {} unless run.reload.metadata.is_a?(Hash)

      run.metadata.deep_stringify_keys
    end

    def normalize_last_run_at(value)
      return value.in_time_zone if value.respond_to?(:in_time_zone)

      raw_value = value.to_s.strip
      return nil if raw_value.blank?

      Time.zone.parse(raw_value)
    rescue ArgumentError
      nil
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
