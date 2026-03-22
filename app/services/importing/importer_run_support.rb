module Importing
  module ImporterRunSupport
    RUN_STATE_CACHE_TTL_SECONDS = 0.001

    private

    def active_running_run(excluding_run_id: nil)
      scope = import_source.import_runs.where(source_type: import_run_source_type, status: "running").order(started_at: :desc)
      scope = scope.where.not(id: excluding_run_id) if excluding_run_id.present?
      scope.first
    end

    def claim_preexisting_run!
      return nil if @preexisting_run_id.blank?

      run = import_source.import_runs.lock.find_by(id: @preexisting_run_id, source_type: import_run_source_type)
      return nil unless run.present?

      if run.status == "running"
        merged_metadata = execution_metadata_for(normalized_metadata(run.metadata).merge(normalized_metadata(run_metadata)))
        if merged_metadata != normalized_metadata(run.metadata)
          run.update!(metadata: merged_metadata)
          broadcast_runs_update!
        end
        return run
      end

      return nil unless run.status == "queued"

      run.update!(
        status: "running",
        metadata: execution_metadata_for(normalized_metadata(run.metadata).merge(normalized_metadata(run_metadata)))
      )
      broadcast_runs_update!
      run
    end

    def preexisting_run_terminal?
      return false if @preexisting_run_id.blank?

      run = import_source.import_runs.find_by(id: @preexisting_run_id, source_type: import_run_source_type)
      return false unless run.present?

      %w[succeeded failed canceled].include?(run.status)
    end

    def should_flush_progress?(changed_since_flush, last_flush_at)
      return true if changed_since_flush >= self.class::PROGRESS_FLUSH_EVERY_N_CHANGES

      (Time.current - last_flush_at) >= self.class::PROGRESS_FLUSH_AFTER_SECONDS
    end

    def persist_progress!(run, fetched_count:, filtered_count:, imported_count:, upserted_count:, failed_count:)
      return unless run_running?(run)

      run.update_columns(
        fetched_count: fetched_count,
        filtered_count: filtered_count,
        imported_count: imported_count,
        upserted_count: upserted_count,
        failed_count: failed_count,
        updated_at: Time.current
      )
      refresh_run_state_cache!(run)
      broadcast_runs_update!
    end

    def stop_requested?(run)
      ActiveModel::Type::Boolean.new.cast(cached_run_state(run).fetch(:metadata, {})["stop_requested"])
    end

    def run_running?(run)
      cached_run_state(run)[:status] == "running"
    end

    def run_canceled?(run)
      cached_run_state(run)[:status] == "canceled"
    end

    def normalized_metadata(metadata)
      return {} unless metadata.is_a?(Hash)

      metadata.deep_stringify_keys
    end

    def stale_run_stop_requested?(run)
      ActiveModel::Type::Boolean.new.cast(normalized_metadata(run.metadata)["stop_requested"])
    end

    def touch_run_heartbeat!(run, extra_metadata: nil)
      return unless run_running?(run)

      metadata = normalized_metadata(run.metadata)
      merged_metadata = metadata.merge(normalized_metadata(extra_metadata))

      if merged_metadata == metadata
        run.update_columns(updated_at: Time.current)
      else
        run.update_columns(updated_at: Time.current, metadata: merged_metadata)
      end
      refresh_run_state_cache!(run)
    end

    def execution_started_at_for(run)
      raw_value = normalized_metadata(run.metadata)["execution_started_at"].to_s.strip
      return nil if raw_value.blank?

      Time.zone.parse(raw_value)
    rescue ArgumentError
      nil
    end

    def broadcast_runs_update!
      Backend::ImportRunsBroadcaster.broadcast!
    rescue StandardError => e
      logger.error("[#{importer_log_prefix}] failed to broadcast run update: #{e.class}: #{e.message}")
    end

    def create_import_run_error!(run:, error:, external_event_id: nil, payload: {})
      return unless run&.persisted?

      run.import_run_errors.create!(
        source_type: run.source_type,
        external_event_id: external_event_id,
        error_class: error.class.to_s,
        message: error.message.to_s.presence || error.class.to_s,
        payload: payload.is_a?(Hash) ? payload : {}
      )
    rescue StandardError => create_error
      logger.error("[#{importer_log_prefix}] failed to persist import run error: #{create_error.class}: #{create_error.message}")
    end

    def add_filtered_out_city!(cities_set, city_value)
      return if cities_set.size >= filtered_out_cities_limit

      city = city_value.to_s.strip
      return if city.blank?

      cities_set << city
    end

    def import_run_source_type
      import_source.source_type
    end

    def execution_metadata_for(metadata)
      metadata = normalized_metadata(metadata)
      metadata["execution_started_at"] ||= Time.current.iso8601
      metadata
    end

    def importer_log_prefix
      "#{self.class.module_parent.name.demodulize}Importer"
    end

    def filtered_out_cities_limit
      self.class::FILTERED_OUT_CITIES_LIMIT
    end

    def cached_run_state(run)
      @cached_run_states ||= {}

      cached_state = @cached_run_states[run.id]
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      if cached_state.nil? || (now - cached_state[:fetched_at]) >= RUN_STATE_CACHE_TTL_SECONDS
        run.reload
        cached_state = {
          fetched_at: now,
          status: run.status,
          metadata: normalized_metadata(run.metadata)
        }
        @cached_run_states[run.id] = cached_state
      end

      cached_state
    end

    def refresh_run_state_cache!(run)
      @cached_run_states ||= {}
      @cached_run_states[run.id] = {
        fetched_at: Process.clock_gettime(Process::CLOCK_MONOTONIC),
        status: run.status,
        metadata: normalized_metadata(run.metadata)
      }
    end
  end
end
