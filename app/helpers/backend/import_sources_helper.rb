module Backend::ImportSourcesHelper
  def import_run_type_label(run)
    case run.source_type
    when "easyticket"
      "Easyticket"
    when "eventim"
      "Eventim"
    when "reservix"
      "Reservix"
    when "merge"
      "Merge"
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
    run.status == "running" && !import_run_stop_requested?(run) && import_run_stop_path(run).present?
  end

  def import_run_stop_path(run)
    case run.source_type
    when "easyticket"
      stop_easyticket_run_backend_import_source_path(run.import_source_id, run_id: run.id)
    when "eventim"
      stop_eventim_run_backend_import_source_path(run.import_source_id, run_id: run.id)
    when "reservix"
      stop_reservix_run_backend_import_source_path(run.import_source_id, run_id: run.id)
    end
  end

  def import_run_filtered_label(run)
    return "-" if run.source_type == "merge"

    run.filtered_count
  end

  def import_run_raw_imports_label(run)
    return merge_import_records_count(run) if run.source_type == "merge"

    run.upserted_count
  end

  def import_run_merge_groups_label(run)
    return "-" unless run.source_type == "merge"

    merge_groups_count(run) || run.imported_count
  end

  def import_run_inserts_label(run)
    return run.upserted_count unless run.source_type == "merge"

    metadata = import_run_metadata(run)
    events_created_count = Integer(metadata["events_created_count"], exception: false)
    return events_created_count if events_created_count

    run.imported_count
  end

  def import_run_updates_label(run)
    return "-" unless run.source_type == "merge"

    metadata = import_run_metadata(run)
    Integer(metadata["events_updated_count"], exception: false) || "-"
  end

  def import_run_duplicates_label(run)
    return "-" unless run.source_type == "merge"

    metadata = import_run_metadata(run)
    Integer(metadata["duplicate_matches_count"], exception: false) || 0
  end

  def import_run_collapsed_records_label(run)
    return "-" unless run.source_type == "merge"

    raw_imports = merge_import_records_count(run)
    groups_count = merge_groups_count(run) || run.imported_count
    return "-" if raw_imports.nil? || groups_count.nil?

    raw_imports - groups_count
  end

  def import_run_retries_label(run)
    retries_used = import_run_retry_metadata_integer(run, "job_retries_used")
    max_retries = import_run_retry_metadata_integer(run, "max_retries")
    return "-" if retries_used.nil? || max_retries.nil?

    "#{retries_used} / #{max_retries}"
  end

  def import_run_filtered_out_cities(run)
    configured_cities = import_source_configured_cities(run.import_source)
    Array(import_run_metadata(run)["filtered_out_cities"])
      .map { |city| city.to_s.strip }
      .reject(&:blank?)
      .reject { |city| configured_cities.any? { |configured| configured.casecmp?(city) } }
      .uniq
      .sort
  end

  def import_source_includes_city?(source, city)
    import_source_configured_cities(source).any? do |entry|
      entry.to_s.strip.casecmp?(city.to_s.strip)
    end
  end

  def import_source_configured_cities(source)
    source
      .configured_location_whitelist
      .map { |city| city.to_s.strip }
      .reject(&:blank?)
      .uniq
      .sort
  end

  private

  def import_run_metadata(run)
    return {} unless run.metadata.is_a?(Hash)

    run.metadata.deep_stringify_keys
  end

  def import_run_retry_metadata_integer(run, key)
    raw_value = import_run_metadata(run)[key]
    return nil if raw_value.nil?

    Integer(raw_value, exception: false)
  end

  def merge_import_records_count(run)
    Integer(import_run_metadata(run)["import_records_count"], exception: false) || run.fetched_count
  end

  def merge_groups_count(run)
    Integer(import_run_metadata(run)["groups_count"], exception: false)
  end
end
