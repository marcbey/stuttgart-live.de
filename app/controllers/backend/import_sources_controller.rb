module Backend
  class ImportSourcesController < BaseController
    before_action :ensure_supported_sources
    before_action :set_import_source, only: [ :edit, :update, :run_easyticket, :stop_easyticket_run, :run_eventim, :stop_eventim_run, :run_reservix, :stop_reservix_run ]
    before_action :set_active_section, only: [ :index, :sync_imported_events, :stop_merge_run, :run_llm_enrichment, :rerun_llm_enrichment, :stop_llm_enrichment_run, :run_llm_genre_grouping, :stop_llm_genre_grouping_run, :edit, :update, :run_easyticket, :stop_easyticket_run, :run_eventim, :stop_eventim_run, :run_reservix, :stop_reservix_run ]

    def index
      run_maintenance.release_stale_running_runs!
      @overview_state = overview_state
      @import_sources = @overview_state.import_sources
      @recent_runs = @overview_state.recent_runs
      @active_section = @overview_state.section(@active_section_key)

      respond_to do |format|
        format.html
        format.json do
          render json: { runs: @recent_runs.map { |run| recent_run_serializer.as_json(run) } }
        end
      end
    end

    def edit
      @return_section = @active_section_key
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
      respond_with_importer_feedback(**start_llm_enrichment_run)
    end

    def rerun_llm_enrichment
      respond_with_importer_feedback(**start_llm_enrichment_run(refresh_existing: true))
    end

    def stop_llm_enrichment_run
      result = llm_run_stopper.call(
        source_type: "llm_enrichment",
        import_source: llm_enrichment_run_source,
        run_id: params[:run_id]
      )

      if result.alert.present?
        respond_with_importer_feedback(alert: "Kein aktiver LLM-Enrichment-Run gefunden.")
        return
      end

      notice =
        case result.action
        when :canceled_queue
          "LLM-Enrichment (Run ##{result.run.id}) wurde aus der Warteschlange entfernt."
        when :forced_cancel
          "LLM-Enrichment (Run ##{result.run.id}) wurde sofort gestoppt."
        else
          "Stop für LLM-Enrichment (Run ##{result.run.id}) wurde angefordert."
        end

      respond_with_importer_feedback(notice:)
    end

    def run_llm_genre_grouping
      respond_with_importer_feedback(**run_manager_for(llm_run_source).trigger("llm_genre_grouping"))
    end

    def stop_llm_genre_grouping_run
      respond_with_importer_feedback(**run_manager_for(llm_run_source).request_stop("llm_genre_grouping", run_id: params[:run_id]))
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

        redirect_to import_sources_redirect_path, notice: "Importer-Konfiguration gespeichert."
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
      llm_run_source
    end

    def start_llm_enrichment_run(refresh_existing: false)
      result = llm_run_enqueuer.call(
        source_type: "llm_enrichment",
        import_source: llm_enrichment_run_source,
        run_metadata: llm_enrichment_run_metadata(refresh_existing:)
      )

      return { alert: result.alert } if result.alert.present?

      if result.dispatched
        return {
          notice: refresh_existing ? "LLM-Enrichment-Re-Run für zukünftige Events wurde gestartet." : "LLM-Enrichment wurde gestartet."
        }
      end

      {
        notice: llm_enrichment_queue_notice(refresh_existing:, queue_position: result.queue_position)
      }
    end

    def llm_enrichment_run_metadata(refresh_existing: false)
      {
        "triggered_at" => Time.current.iso8601,
        "refresh_existing" => refresh_existing
      }
    end

    def llm_run_source
      importer_registry.resolve_run_source("llm_enrichment")
    end

    def set_import_source
      @import_source = ImportSource.includes(:import_source_config).find(params[:id])
    end

    def import_source_params
      params.require(:import_source).permit(:active, :location_whitelist_text)
    end

    def set_active_section
      @active_section_key = Backend::ImportSources::OverviewState.normalized_section_key(params[:section])
    end

    def overview_state
      @overview_state ||= Backend::ImportSources::OverviewState.new
    end

    def importer_registry
      @importer_registry ||= Backend::ImportSources::ImporterRegistry.new
    end

    def run_maintenance
      @run_maintenance ||= Backend::ImportSources::RunMaintenance.new(registry: importer_registry)
    end

    def run_manager
      @run_manager ||= run_manager_for(@import_source)
    end

    def run_manager_for(import_source)
      Backend::ImportSources::RunManager.new(
        import_source: import_source,
        registry: importer_registry,
        maintenance: run_maintenance
      )
    end

    def llm_run_dispatcher
      @llm_run_dispatcher ||= Backend::ImportSources::RunDispatcher.new(registry: importer_registry)
    end

    def llm_run_enqueuer
      @llm_run_enqueuer ||= Backend::ImportSources::RunEnqueuer.new(
        registry: importer_registry,
        maintenance: run_maintenance,
        dispatcher: llm_run_dispatcher
      )
    end

    def llm_run_stopper
      @llm_run_stopper ||= Backend::ImportSources::RunStopper.new(
        registry: importer_registry,
        dispatcher: llm_run_dispatcher
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
      Backend::ImportRunsBroadcaster.recent_runs_for_list
    end

    def respond_with_importer_feedback(notice: nil, alert: nil)
      respond_to do |format|
        format.html do
          if alert.present?
            redirect_to import_sources_redirect_path, alert: alert
          elsif notice.present?
            redirect_to import_sources_redirect_path, notice: notice
          else
            redirect_to import_sources_redirect_path
          end
        end

        format.turbo_stream do
          flash.now[:notice] = notice if notice.present?
          flash.now[:alert] = alert if alert.present?
          state = overview_state

          render turbo_stream: [
            turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
            turbo_stream.replace(
              "import-runs-live-shell",
              partial: "backend/import_sources/live_shell",
              locals: {
                sections: state.sections,
                active_section_key: @active_section_key,
                overview_state: state,
                import_sources: state.import_sources
              }
            )
          ]
        end
      end
    end

    def trigger_merge_sync
      result = Backend::ImportSources::MergeRunStarter.new.call
      { notice: result.notice, alert: result.alert }
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

    def llm_enrichment_queue_notice(refresh_existing:, queue_position:)
      base_message =
        if refresh_existing
          "LLM-Enrichment-Re-Run für zukünftige Events wurde zur Warteschlange hinzugefügt"
        else
          "LLM-Enrichment wurde zur Warteschlange hinzugefügt"
        end

      return "#{base_message}." if queue_position.blank?

      "#{base_message} (Position #{queue_position})."
    end

    def import_sources_redirect_path
      if @active_section_key == Backend::ImportSources::OverviewState::DEFAULT_SECTION && params[:section].blank?
        return backend_import_sources_path
      end

      backend_import_sources_path(section: @active_section_key)
    end
  end
end
