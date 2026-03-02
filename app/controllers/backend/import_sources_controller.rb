module Backend
  class ImportSourcesController < ApplicationController
    before_action :ensure_easyticket_source
    before_action :set_import_source, only: [ :edit, :update, :run_easyticket, :stop_easyticket_run ]

    def index
      @import_sources = ImportSource.includes(:import_source_config).order(:source_type)
      @recent_runs = ImportRun.where(source_type: "easyticket").recent.limit(10)

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

      running_run = @import_source.import_runs.where(source_type: "easyticket", status: "running").order(started_at: :desc).first
      if running_run.present? && !release_stale_running_run!(running_run)
        redirect_to backend_import_sources_path, alert: "Ein Easyticket-Import laeuft bereits (Run ##{running_run.id})."
        return
      end

      Importing::Easyticket::RunJob.perform_later(@import_source.id)
      redirect_to backend_import_sources_path, notice: "Easyticket-Import wurde gestartet."
    end

    def stop_easyticket_run
      unless @import_source.easyticket?
        redirect_to backend_import_sources_path, alert: "Nur Easyticket kann hier gestoppt werden."
        return
      end

      run = find_running_run_for_stop
      unless run
        redirect_to backend_import_sources_path, alert: "Kein laufender Easyticket-Import gefunden."
        return
      end

      metadata = normalized_metadata(run.metadata)
      metadata["stop_requested"] = true
      metadata["stop_requested_at"] = Time.current.iso8601
      run.update!(metadata: metadata)
      Backend::EasyticketImportRunsBroadcaster.broadcast!

      redirect_to backend_import_sources_path, notice: "Stop fuer Easyticket-Import (Run ##{run.id}) wurde angefordert."
    end

    private

    def ensure_easyticket_source
      ImportSource.ensure_easyticket_source!
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
        fetched_count: run.fetched_count,
        filtered_count: run.filtered_count,
        imported_count: run.imported_count,
        upserted_count: run.upserted_count,
        failed_count: run.failed_count,
        can_stop: can_stop,
        stop_url: can_stop ? stop_easyticket_run_backend_import_source_path(run.import_source_id, run_id: run.id) : nil
      }
    end

    def find_running_run_for_stop
      scope = @import_source.import_runs.where(source_type: "easyticket", status: "running").order(started_at: :desc)
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

    def release_stale_running_run!(run)
      if run.started_at < Importing::Easyticket::Importer::RUN_STALE_AFTER.ago
        fail_stale_run!(run)
        return true
      end

      if stop_requested_stale?(run)
        cancel_stale_stop_requested_run!(run)
        return true
      end

      false
    end

    def stop_requested_stale?(run)
      return false unless run_stop_requested?(run)
      run.updated_at < Importing::Easyticket::Importer::RUN_HEARTBEAT_STALE_AFTER.ago
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
      Backend::EasyticketImportRunsBroadcaster.broadcast!
    end

    def fail_stale_run!(run)
      metadata = normalized_metadata(run.metadata)
      metadata["stale_released_at"] = Time.current.iso8601
      metadata["stale_release_reason"] = "Run exceeded stale timeout"
      run.update!(
        status: "failed",
        finished_at: Time.current,
        metadata: metadata,
        error_message: "Run automatically marked failed after timeout (#{Importing::Easyticket::Importer::RUN_STALE_AFTER.inspect})"
      )
      Backend::EasyticketImportRunsBroadcaster.broadcast!
    end
  end
end
