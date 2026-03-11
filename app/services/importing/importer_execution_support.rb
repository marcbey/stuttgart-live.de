require "set"

module Importing
  module ImporterExecutionSupport
    PreparationResult = Data.define(:run, :process)

    private

    def prepare_import_run!
      run = nil
      process = true

      import_source.with_lock do
        fail_stale_runs!
        run = claim_preexisting_run!
        active_run = active_running_run if run.nil?
        if active_run.present?
          logger.info("[#{importer_log_prefix}] skipped because run_id=#{active_run.id} is already running")
          run = active_run
          process = false
        elsif run.nil?
          run = import_source.import_runs.create!(
            status: "running",
            source_type: import_source.source_type,
            started_at: Time.current,
            metadata: normalized_metadata(run_metadata)
          )
          broadcast_runs_update!
        end
      end

      PreparationResult.new(run:, process:)
    end

    def initial_run_state(run:, **extra)
      {
        run_started_at: run.started_at,
        fetched_count: 0,
        filtered_count: 0,
        imported_count: 0,
        upserted_count: 0,
        failed_count: 0,
        canceled: false,
        location_whitelist: import_source.configured_location_whitelist,
        filtered_out_cities: Set.new
      }.merge(extra)
    end

    def persist_progress_from_state!(run, state)
      persist_progress!(
        run,
        fetched_count: state[:fetched_count],
        filtered_count: state[:filtered_count],
        imported_count: state[:imported_count],
        upserted_count: state[:upserted_count],
        failed_count: state[:failed_count]
      )
    end

    def finalize_canceled_run!(run, state, metadata:)
      run.update!(
        status: "canceled",
        finished_at: Time.current,
        fetched_count: state[:fetched_count],
        filtered_count: state[:filtered_count],
        imported_count: state[:imported_count],
        upserted_count: state[:upserted_count],
        failed_count: state[:failed_count],
        metadata: metadata
      )
      broadcast_runs_update!
      run
    end

    def finalize_succeeded_run!(run, state, metadata:)
      run.update!(
        status: "succeeded",
        finished_at: Time.current,
        fetched_count: state[:fetched_count],
        filtered_count: state[:filtered_count],
        imported_count: state[:imported_count],
        upserted_count: state[:upserted_count],
        failed_count: state[:failed_count],
        metadata: metadata
      )
      broadcast_runs_update!
      run
    end

    def handle_import_failure!(run, state, error:, metadata:)
      return run.reload if run&.persisted? && run_canceled?(run)

      run&.update!(
        status: "failed",
        finished_at: Time.current,
        fetched_count: state&.fetch(:fetched_count, 0) || 0,
        filtered_count: state&.fetch(:filtered_count, 0) || 0,
        imported_count: state&.fetch(:imported_count, 0) || 0,
        upserted_count: state&.fetch(:upserted_count, 0) || 0,
        failed_count: state&.fetch(:failed_count, 0) || 0,
        error_message: error.message,
        metadata: metadata
      )
      create_import_run_error!(
        run: run,
        error: error,
        payload: {}
      )
      broadcast_runs_update!
      nil
    end

    def fail_stale_runs_by_source!(source_type)
      stale_runs =
        import_source
          .import_runs
          .where(source_type: source_type, status: "running")
          .where("started_at < ? OR updated_at < ?", self.class::RUN_STALE_AFTER.ago, self.class::RUN_HEARTBEAT_STALE_AFTER.ago)
          .to_a

      return if stale_runs.empty?

      stale_runs.each do |stale_run|
        if stale_run.started_at < self.class::RUN_STALE_AFTER.ago
          stale_run.update_columns(
            status: "failed",
            finished_at: Time.current,
            error_message: "Run automatically marked failed after timeout (#{self.class::RUN_STALE_AFTER.inspect})",
            updated_at: Time.current
          )
        elsif stale_run_stop_requested?(stale_run)
          stale_run.update_columns(
            status: "canceled",
            finished_at: Time.current,
            updated_at: Time.current
          )
        else
          stale_run.update_columns(
            status: "failed",
            finished_at: Time.current,
            error_message: "Run automatically marked failed after heartbeat timeout (#{self.class::RUN_HEARTBEAT_STALE_AFTER.inspect})",
            updated_at: Time.current
          )
        end
      end
      broadcast_runs_update!
    end
  end
end
