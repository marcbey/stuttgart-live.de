module Backend
  class ImportSourcesController < BaseController
    before_action :ensure_supported_sources
    before_action :set_import_source, only: [ :edit, :update, :run_easyticket, :stop_easyticket_run, :run_eventim, :stop_eventim_run ]

    def index
      release_stale_running_runs!
      @import_sources = ImportSource.includes(:import_source_config).order(:source_type)
      @recent_runs = ImportRun.where(source_type: Backend::ImportRunsBroadcaster::SUPPORTED_SOURCE_TYPES).recent.limit(20)

      respond_to do |format|
        format.html
        format.json do
          render json: { runs: @recent_runs.map { |run| serialize_run(run) } }
        end
      end
    end

    def edit
    end

    def update
      @import_source.assign_attributes(
        name: import_source_params[:name],
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
      unless @import_source.easyticket?
        redirect_to backend_import_sources_path, alert: "Nur Easyticket kann hier gestartet werden."
        return
      end

      trigger_import!(
        source_type: "easyticket",
        label: "Easyticket",
        run_job_class: Importing::Easyticket::RunJob
      )
    end

    def run_eventim
      unless @import_source.eventim?
        redirect_to backend_import_sources_path, alert: "Nur Eventim kann hier gestartet werden."
        return
      end

      trigger_import!(
        source_type: "eventim",
        label: "Eventim",
        run_job_class: Importing::Eventim::RunJob
      )
    end

    def stop_easyticket_run
      unless @import_source.easyticket?
        redirect_to backend_import_sources_path, alert: "Nur Easyticket kann hier gestoppt werden."
        return
      end

      request_stop_for_running_import!(source_type: "easyticket", label: "Easyticket")
    end

    def stop_eventim_run
      unless @import_source.eventim?
        redirect_to backend_import_sources_path, alert: "Nur Eventim kann hier gestoppt werden."
        return
      end

      request_stop_for_running_import!(source_type: "eventim", label: "Eventim")
    end

    private

    def ensure_supported_sources
      ImportSource.ensure_supported_sources!
    end

    def set_import_source
      @import_source = ImportSource.includes(:import_source_config).find(params[:id])
    end

    def import_source_params
      params.require(:import_source).permit(:name, :active, :location_whitelist_text)
    end

    def serialize_run(run)
      stop_requested = run_stop_requested?(run)
      can_stop = run.status == "running" && !stop_requested
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
        stop_url: stop_url_for(run, can_stop: can_stop)
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
      running_run = @import_source.import_runs.where(source_type: source_type, status: "running").order(started_at: :desc).first
      if running_run.present? && !release_stale_running_run!(running_run)
        redirect_to backend_import_sources_path, alert: "Ein #{label}-Import laeuft bereits (Run ##{running_run.id})."
        return
      end

      run_job_class.perform_later(@import_source.id)
      redirect_to backend_import_sources_path, notice: "#{label}-Import wurde gestartet."
    end

    def request_stop_for_running_import!(source_type:, label:)
      run = find_running_run_for_stop(source_type)
      unless run
        redirect_to backend_import_sources_path, alert: "Kein laufender #{label}-Import gefunden."
        return
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

      redirect_to backend_import_sources_path, notice: "Stop fuer #{label}-Import (Run ##{run.id}) wurde angefordert."
    end

    def release_stale_running_run!(run)
      if run.started_at < importer_class_for(run.source_type)::RUN_STALE_AFTER.ago
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
            timeout_value: importer_class_for(run.source_type)::RUN_HEARTBEAT_STALE_AFTER
          )
        end
        return true
      end

      false
    end

    def release_stale_running_runs!
      ImportRun
        .where(source_type: Backend::ImportRunsBroadcaster::SUPPORTED_SOURCE_TYPES, status: "running")
        .find_each do |run|
        release_stale_running_run!(run)
      end
    end

    def heartbeat_stale?(run)
      run.updated_at < importer_class_for(run.source_type)::RUN_HEARTBEAT_STALE_AFTER.ago
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
      timeout_value ||= importer_class_for(run.source_type)::RUN_STALE_AFTER
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

      case run.source_type
      when "easyticket"
        stop_easyticket_run_backend_import_source_path(run.import_source_id, run_id: run.id)
      when "eventim"
        stop_eventim_run_backend_import_source_path(run.import_source_id, run_id: run.id)
      end
    end

    def importer_class_for(source_type)
      case source_type
      when "eventim"
        Importing::Eventim::Importer
      else
        Importing::Easyticket::Importer
      end
    end
  end
end
