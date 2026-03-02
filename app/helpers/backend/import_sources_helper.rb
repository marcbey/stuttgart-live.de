module Backend::ImportSourcesHelper
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

  private

  def import_run_metadata(run)
    return {} unless run.metadata.is_a?(Hash)

    run.metadata.deep_stringify_keys
  end
end
