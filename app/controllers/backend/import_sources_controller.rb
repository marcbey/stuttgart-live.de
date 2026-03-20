module Backend
  class ImportSourcesController < BaseController
    before_action :ensure_supported_sources
    before_action :set_import_source, only: [ :edit, :update, :run_easyticket, :stop_easyticket_run, :run_eventim, :stop_eventim_run, :run_reservix, :stop_reservix_run ]

    def index
      run_maintenance.release_stale_running_runs!
      @import_sources = ImportSource.includes(:import_source_config).order(:source_type)
      @recent_runs = recent_runs_for_list
      @merge_sync_needed = merge_sync_needed?

      respond_to do |format|
        format.html
        format.json do
          render json: { runs: @recent_runs.map { |run| recent_run_serializer.as_json(run) } }
        end
      end
    end

    def edit
    end

    def sync_imported_events
      respond_with_importer_feedback(**trigger_merge_sync)
    end

    def stop_merge_run
      run = ImportRun.where(source_type: "merge", status: "running").order(started_at: :desc)
      run = run.find_by(id: params[:run_id]) if params[:run_id].present?
      run ||= ImportRun.where(source_type: "merge", status: "running").order(started_at: :desc).first

      if run.blank?
        respond_with_importer_feedback(alert: "Kein laufender Merge-Run gefunden.")
        return
      end

      metadata = run.metadata.is_a?(Hash) ? run.metadata.deep_stringify_keys : {}
      metadata["stop_requested"] = true
      metadata["stop_requested_at"] = Time.current.iso8601
      run.update!(metadata: metadata)

      Backend::ImportRunsBroadcaster.broadcast!
      respond_with_importer_feedback(notice: "Stop für Merge-Run ##{run.id} wurde angefordert.")
    end

    def run_llm_enrichment
      source = llm_enrichment_run_source
      feedback = nil
      broadcast = false

      source.with_lock do
        active_run = source.import_runs.where(source_type: "llm_enrichment", status: "running").order(started_at: :desc).first
        if active_run.present?
          feedback = { alert: "Ein LLM-Enrichment-Lauf läuft bereits (Run ##{active_run.id})." }
          next
        end

        run = source.import_runs.create!(
          status: "running",
          source_type: "llm_enrichment",
          started_at: Time.current,
          metadata: { "triggered_at" => Time.current.iso8601 }
        )
        job = Importing::LlmEnrichment::RunJob.perform_later(run.id)
        run.update!(
          metadata: run.metadata.merge(
            "job_id" => job.job_id,
            "provider_job_id" => job.provider_job_id,
            "job_attempt" => 1,
            "job_retries_used" => 0,
            "max_retries" => 0
          )
        )
        feedback = { notice: "LLM-Enrichment wurde gestartet." }
        broadcast = true
      end

      Backend::ImportRunsBroadcaster.broadcast! if broadcast
      respond_with_importer_feedback(**feedback)
    end

    def stop_llm_enrichment_run
      source = llm_enrichment_run_source
      run = source.import_runs.where(source_type: "llm_enrichment", status: "running").order(started_at: :desc)
      run = run.find_by(id: params[:run_id]) if params[:run_id].present?
      run ||= source.import_runs.where(source_type: "llm_enrichment", status: "running").order(started_at: :desc).first

      if run.blank?
        respond_with_importer_feedback(alert: "Kein laufender LLM-Enrichment-Run gefunden.")
        return
      end

      metadata = run.metadata.is_a?(Hash) ? run.metadata.deep_stringify_keys : {}
      metadata["stop_requested"] = true
      metadata["stop_requested_at"] = Time.current.iso8601
      run.update!(metadata: metadata)

      Backend::ImportRunsBroadcaster.broadcast!
      respond_with_importer_feedback(notice: "Stop für LLM-Enrichment (Run ##{run.id}) wurde angefordert.")
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

    def llm_enrichment_run_source
      ImportSource.find_by(source_type: "eventim") ||
        ImportSource.find_by(source_type: "easyticket") ||
        ImportSource.ensure_eventim_source!
    end

    def merge_run_source
      llm_enrichment_run_source
    end

    def set_import_source
      @import_source = ImportSource.includes(:import_source_config).find(params[:id])
    end

    def import_source_params
      params.require(:import_source).permit(:active, :location_whitelist_text)
    end

    def importer_registry
      @importer_registry ||= Backend::ImportSources::ImporterRegistry.new
    end

    def run_maintenance
      @run_maintenance ||= Backend::ImportSources::RunMaintenance.new(registry: importer_registry)
    end

    def run_manager
      @run_manager ||= Backend::ImportSources::RunManager.new(
        import_source: @import_source,
        registry: importer_registry,
        maintenance: run_maintenance
      )
    end

    def recent_run_serializer
      @recent_run_serializer ||= Backend::ImportSources::RecentRunSerializer.new(
        controller: self,
        registry: importer_registry,
        maintenance: run_maintenance
      )
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
            turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
            turbo_stream.replace(
              "import-runs-table",
              partial: "backend/import_sources/recent_runs_table",
              locals: { recent_runs: recent_runs_for_list }
            )
          ]
        end
      end
    end

    def trigger_merge_sync
      result = nil
      run_source = merge_run_source

      run_source.with_lock do
        active_run = ImportRun.where(source_type: "merge", status: "running").order(started_at: :desc).first
        if active_run.present?
          result = { alert: "Ein Merge-Run läuft bereits (Run ##{active_run.id})." }
          next
        end

        run = ImportRun.create!(
          import_source: run_source,
          source_type: "merge",
          status: "running",
          started_at: Time.current,
          metadata: { "triggered_at" => Time.current.iso8601 }
        )
        Merging::SyncImportedEventsJob.perform_later(import_run_id: run.id)
        Backend::ImportRunsBroadcaster.broadcast!
        result = { notice: "Merge-Sync wurde gestartet." }
      end

      result
    end

    def run_import_for(source_type)
      unless @import_source.source_type == source_type
        respond_with_importer_feedback(alert: "Nur #{importer_registry.fetch(source_type).fetch(:label)} kann hier gestartet werden.")
        return
      end

      respond_with_importer_feedback(**run_manager.trigger(source_type))
    end

    def stop_import_for(source_type)
      unless @import_source.source_type == source_type
        respond_with_importer_feedback(alert: "Nur #{importer_registry.fetch(source_type).fetch(:label)} kann hier gestoppt werden.")
        return
      end

      respond_with_importer_feedback(**run_manager.request_stop(source_type, run_id: params[:run_id]))
    end
  end
end
