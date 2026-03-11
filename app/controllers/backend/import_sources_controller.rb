module Backend
  class ImportSourcesController < BaseController
    IMPORTER_CONFIG = {
      "easyticket" => {
        label: "Easyticket",
        run_job_class: Importing::Easyticket::RunJob,
        importer_class: Importing::Easyticket::Importer,
        stop_route_helper: :stop_easyticket_run_backend_import_source_path
      },
      "eventim" => {
        label: "Eventim",
        run_job_class: Importing::Eventim::RunJob,
        importer_class: Importing::Eventim::Importer,
        stop_route_helper: :stop_eventim_run_backend_import_source_path
      },
      "reservix" => {
        label: "Reservix",
        run_job_class: Importing::Reservix::RunJob,
        importer_class: Importing::Reservix::Importer,
        stop_route_helper: :stop_reservix_run_backend_import_source_path
      }
    }.freeze
    IMPORTER_SOURCE_TYPES = IMPORTER_CONFIG.keys.freeze

    before_action :ensure_supported_sources
    before_action :set_import_source, only: [ :edit, :update, :run_easyticket, :stop_easyticket_run, :run_eventim, :stop_eventim_run, :run_reservix, :stop_reservix_run ]

    def index
      release_stale_running_runs!
      @import_sources = ImportSource.includes(:import_source_config).order(:source_type)
      @recent_runs = recent_runs_for_list
      @merge_sync_needed = merge_sync_needed?

      respond_to do |format|
        format.html
        format.json do
          render json: { runs: @recent_runs.map { |run| serialize_run(run) } }
        end
      end
    end

    def edit
    end

    def sync_imported_events
      Merging::SyncImportedEventsJob.perform_later
      redirect_to backend_import_sources_path, notice: "Merge-Sync wurde gestartet."
    end

    def update
      @import_source.assign_attributes(
        active: import_source_params[:active] == "1"
      )

      config = @import_source.import_source_config || @import_source.build_import_source_config
      config.location_whitelist = import_source_params[:location_whitelist_text].to_s

      if @import_source.valid? && config.valid?
        ImportSource.transaction do
          @import_source.save!
          config.save!
        end

        redirect_to backend_import_sources_path, notice: "Importer-Konfiguration gespeichert."
      else
        flash.now[:alert] = "Konfiguration konnte nicht gespeichert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    def run_easyticket
      run_import_for("easyticket")
    end

    def run_eventim
      run_import_for("eventim")
    end

    def stop_easyticket_run
      stop_import_for("easyticket")
    end

    def stop_eventim_run
      stop_import_for("eventim")
    end

    def run_reservix
      run_import_for("reservix")
    end

    def stop_reservix_run
      stop_import_for("reservix")
    end

    private

    def ensure_supported_sources
      ImportSource.ensure_supported_sources!
    end

    def set_import_source
      @import_source = ImportSource.includes(:import_source_config).find(params[:id])
    end

    def import_source_params
      params.require(:import_source).permit(:active, :location_whitelist_text)
    end

    def serialize_run(run)
      stop_requested = run_stop_requested?(run)
      stop_url = stop_url_for(run, can_stop: true)
      can_stop = run.status == "running" && !stop_requested && stop_url.present?
      {
        id: run.id,
        import_source_id: run.import_source_id,
        started_at_label: run.started_at&.strftime("%d.%m.%Y %H:%M:%S"),
        status_label: run_status_label(run, stop_requested: stop_requested),
        status: run.status,
        source_type: run.source_type,
        fetched_count: run.fetched_count,
        filtered_count: run.filtered_count,
        imported_count: run.imported_count,
        upserted_count: run.upserted_count,
        failed_count: run.failed_count,
        can_stop: can_stop,
        stop_url: can_stop ? stop_url : nil
      }
    end

    def find_running_run_for_stop(source_type)
      scope = @import_source.import_runs.where(source_type: source_type, status: "running").order(started_at: :desc)
      return scope.find_by(id: params[:run_id]) if params[:run_id].present?

      scope.first
    end

    def normalized_metadata(metadata)
      return {} unless metadata.is_a?(Hash)

      metadata.deep_stringify_keys
    end

    def run_stop_requested?(run)
      ActiveModel::Type::Boolean.new.cast(normalized_metadata(run.metadata)["stop_requested"])
    end

    def run_status_label(run, stop_requested:)
      return "running (stop angefordert)" if run.status == "running" && stop_requested

      run.status
    end

    def trigger_import!(source_type:, label:, run_job_class:)
      config = importer_config_for(source_type)
      label ||= config.fetch(:label)
      run_job_class ||= config.fetch(:run_job_class)

      active_run = @import_source.import_runs.where(source_type: source_type, status: %w[queued running]).order(started_at: :desc).first
      if active_run&.status == "running" && release_stale_running_run!(active_run)
        active_run = nil
      end

      if active_run.present?
        message =
          if active_run.status == "queued"
            "Ein #{label}-Import ist bereits eingeplant (Run ##{active_run.id})."
          else
            "Ein #{label}-Import läuft bereits (Run ##{active_run.id})."
          end
        return { alert: message }
      end

      queued_run = @import_source.import_runs.create!(
        status: "queued",
        source_type: source_type,
        started_at: Time.current,
        metadata: { "queued_at" => Time.current.iso8601 }
      )
      job = run_job_class.perform_later(@import_source.id, queued_run.id)
      queued_run.update!(
        metadata: normalized_metadata(queued_run.metadata).merge(
          "job_id" => job.job_id,
          "provider_job_id" => job.provider_job_id,
          "job_attempt" => 1,
          "job_retries_used" => 0,
          "max_retries" => Importing::RetryPolicy::RETRY_DELAYS.size
        )
      )
      Backend::ImportRunsBroadcaster.broadcast!
      {}
    end

    def request_stop_for_running_import!(source_type:, label:)
      label ||= importer_config_for(source_type).fetch(:label)
      run = find_running_run_for_stop(source_type)
      unless run
        return { alert: "Kein laufender #{label}-Import gefunden." }
      end

      metadata = normalized_metadata(run.metadata)
      metadata["stop_requested"] = true
      metadata["stop_requested_at"] = Time.current.iso8601
      metadata["stop_released_at"] = Time.current.iso8601
      metadata["stop_release_reason"] = "Stopped by user"
      run.update!(
        status: "canceled",
        finished_at: Time.current,
        metadata: metadata
      )
      Backend::ImportRunsBroadcaster.broadcast!

      { notice: "Stop für #{label}-Import (Run ##{run.id}) wurde angefordert." }
    end

    def recent_runs_for_list
      ImportRun
        .where(source_type: Backend::ImportRunsBroadcaster::LISTED_SOURCE_TYPES)
        .recent
        .limit(Backend::ImportRunsBroadcaster::RECENT_RUNS_LIMIT)
    end

    def merge_sync_needed?
      latest_import_success_at = latest_successful_run_finished_at_for(source_types: %w[easyticket reservix eventim])
      return false if latest_import_success_at.blank?

      latest_merge_success_at = latest_successful_run_finished_at_for(source_types: [ "merge" ])
      latest_merge_success_at.blank? || latest_import_success_at > latest_merge_success_at
    end

    def latest_successful_run_finished_at_for(source_types:)
      ImportRun.where(source_type: source_types, status: "succeeded").maximum(:finished_at)
    end

    def respond_with_importer_feedback(notice: nil, alert: nil)
      respond_to do |format|
        format.html do
          if alert.present?
            redirect_to backend_import_sources_path, alert: alert
          elsif notice.present?
            redirect_to backend_import_sources_path, notice: notice
          else
            redirect_to backend_import_sources_path
          end
        end

        format.turbo_stream do
          flash.now[:notice] = notice if notice.present?
          flash.now[:alert] = alert if alert.present?

          render turbo_stream: [
            turbo_stream.replace("flash-messages", partial: "layouts/flash_messages"),
            turbo_stream.replace(
              "import-runs-table",
              partial: "backend/import_sources/recent_runs_table",
              locals: { recent_runs: recent_runs_for_list }
            )
          ]
        end
      end
    end

    def release_stale_running_run!(run)
      if run.started_at < importer_config_for(run.source_type).fetch(:importer_class)::RUN_STALE_AFTER.ago
        fail_stale_run!(run)
        return true
      end

      if heartbeat_stale?(run)
        if run_stop_requested?(run)
          cancel_stale_stop_requested_run!(run)
        else
          fail_stale_run!(
            run,
            reason: "Run exceeded heartbeat timeout",
            timeout_value: importer_config_for(run.source_type).fetch(:importer_class)::RUN_HEARTBEAT_STALE_AFTER
          )
        end
        return true
      end

      false
    end

    def release_stale_running_runs!
      ImportRun
        .where(source_type: IMPORTER_SOURCE_TYPES, status: "running")
        .find_each do |run|
        release_stale_running_run!(run)
      end
    end

    def heartbeat_stale?(run)
      run.updated_at < importer_config_for(run.source_type).fetch(:importer_class)::RUN_HEARTBEAT_STALE_AFTER.ago
    end

    def cancel_stale_stop_requested_run!(run)
      metadata = normalized_metadata(run.metadata)
      metadata["stop_released_at"] = Time.current.iso8601
      metadata["stop_release_reason"] = "No progress update after stop request"
      run.update!(
        status: "canceled",
        finished_at: Time.current,
        metadata: metadata
      )
      Backend::ImportRunsBroadcaster.broadcast!
    end

    def fail_stale_run!(run, reason: "Run exceeded stale timeout", timeout_value: nil)
      timeout_value ||= importer_config_for(run.source_type).fetch(:importer_class)::RUN_STALE_AFTER
      metadata = normalized_metadata(run.metadata)
      metadata["stale_released_at"] = Time.current.iso8601
      metadata["stale_release_reason"] = reason
      run.update!(
        status: "failed",
        finished_at: Time.current,
        metadata: metadata,
        error_message: "Run automatically marked failed after timeout (#{timeout_value.inspect})"
      )
      Backend::ImportRunsBroadcaster.broadcast!
    end

    def stop_url_for(run, can_stop:)
      return nil unless can_stop

      helper_name = importer_config_for(run.source_type, required: false)&.fetch(:stop_route_helper, nil)
      return nil if helper_name.blank?

      public_send(helper_name, run.import_source_id, run_id: run.id)
    end

    def run_import_for(source_type)
      unless @import_source.source_type == source_type
        respond_with_importer_feedback(alert: "Nur #{importer_config_for(source_type).fetch(:label)} kann hier gestartet werden.")
        return
      end

      respond_with_importer_feedback(
        **trigger_import!(source_type: source_type, label: nil, run_job_class: nil)
      )
    end

    def stop_import_for(source_type)
      unless @import_source.source_type == source_type
        respond_with_importer_feedback(alert: "Nur #{importer_config_for(source_type).fetch(:label)} kann hier gestoppt werden.")
        return
      end

      respond_with_importer_feedback(
        **request_stop_for_running_import!(source_type: source_type, label: nil)
      )
    end

    def importer_config_for(source_type, required: true)
      config = IMPORTER_CONFIG[source_type.to_s]
      return config if config.present? || !required

      raise KeyError, "key not found: #{source_type.inspect}"
    end
  end
end
