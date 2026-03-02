module Backend::ImportSourcesHelper
  def import_run_type_label(run)
    case run.source_type
    when "easyticket"
      "Easyticket"
    when "eventim"
      "Eventim"
    else
      run.source_type.to_s
    end
  end

  def import_run_stop_requested?(run)
    ActiveModel::Type::Boolean.new.cast(import_run_metadata(run)["stop_requested"])
  end

  def import_run_status_label(run)
    return "running (stop angefordert)" if run.status == "running" && import_run_stop_requested?(run)

    run.status
  end

  def import_run_can_stop?(run)
    run.status == "running" && !import_run_stop_requested?(run)
  end

  def import_run_stop_path(run)
    case run.source_type
    when "easyticket"
      stop_easyticket_run_backend_import_source_path(run.import_source_id, run_id: run.id)
    when "eventim"
      stop_eventim_run_backend_import_source_path(run.import_source_id, run_id: run.id)
    end
  end

  private

  def import_run_metadata(run)
    return {} unless run.metadata.is_a?(Hash)

    run.metadata.deep_stringify_keys
  end
end
