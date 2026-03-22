module Backend::ImportSourcesHelper
  IMPORT_RUN_COLUMN_DESCRIPTIONS = {
    raw_imports: "Provider-Importer: Anzahl der in diesem Lauf geschriebenen Rohimporte. Merge: Anzahl der aktuellen Import-Records nach Auswahl der neuesten Rohimporte je source_identifier. LLM-Enrichment: Anzahl der aus dem letzten Merge-Lauf ausgewählten Events. LLM-Genre-Gruppierung: Anzahl der ausgewählten eindeutigen Genres.",
    merge_groups: "Nur für Merge-Läufe: Anzahl der providerübergreifenden Gruppen nach Dublettenzusammenführung über Artist und Startzeit.",
    filtered: "Nur für Provider-Läufe: Anzahl der Datensätze, die die Orts- und Importfilter passiert haben. LLM-Enrichment: Anzahl bereits übersprungener Events mit vorhandenem Enrichment. LLM-Genre-Gruppierung: Anzahl verworfener Rohgenre-Werte nach Normalisierung.",
    inserts: "Provider-Importer: entspricht den geschriebenen Rohimporten dieses Laufs. Merge: Anzahl der neu angelegten Events. LLM-Enrichment: Anzahl gespeicherter bzw. aktualisierter Enrichments. LLM-Genre-Gruppierung: Anzahl gespeicherter Obergruppen.",
    updates: "Nur für Merge-Läufe: Anzahl bestehender Events, die in diesem Lauf aktualisiert wurden. Überschrieben werden dabei start_at, doors_at, venue, badge_text, min_price, max_price, primary_source, source_fingerprint und source_snapshot.",
    similarity_duplicates: "Nur für Merge-Läufe: Teilmenge der Updates, bei denen das Ähnlichkeits-Matching ein Import-Record einem bestehenden Event zugeordnet hat.",
    collapsed_records: "Nur für Merge-Läufe: Differenz aus Raw Imports und Merge Groups. Zeigt, wie viele aktuelle Rohimporte vor dem finalen Event-Upsert zu gemeinsamen Merge-Gruppen zusammengefasst wurden. LLM-Enrichment: Anzahl der an OpenAI gesendeten Batches. LLM-Genre-Gruppierung: Anzahl der an OpenAI gesendeten Requests."
  }.freeze

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
    when "llm_enrichment"
      "LLM Enrichment"
    when "llm_genre_grouping"
      "LLM-Genre-Gruppierung"
    else
      run.source_type.to_s
    end
  end

  def merge_sync_needed_for_importer_jobs?
    latest_import_success_at = ImportRun.where(source_type: %w[easyticket reservix eventim], status: "succeeded").maximum(:finished_at)
    return false if latest_import_success_at.blank?

    latest_merge_success_at = ImportRun.where(source_type: "merge", status: "succeeded").maximum(:finished_at)
    latest_merge_success_at.blank? || latest_import_success_at > latest_merge_success_at
  end

  def raw_import_run?(run)
    %w[easyticket eventim reservix].include?(run.source_type.to_s)
  end

  def merge_import_run?(run)
    run.source_type.to_s == "merge"
  end

  def llm_import_run?(run)
    run.source_type.to_s == "llm_enrichment"
  end

  def llm_genre_grouping_import_run?(run)
    run.source_type.to_s == "llm_genre_grouping"
  end

  def import_run_stop_requested?(run)
    ActiveModel::Type::Boolean.new.cast(import_run_metadata(run)["stop_requested"])
  end

  def import_run_status_label(run)
    return "stopping" if run.status == "running" && import_run_stop_requested?(run)

    run.status
  end

  def import_run_can_stop?(run, section: nil)
    return false if import_run_stop_path(run, section: section).blank?
    return true if run.status == "queued"

    run.status == "running" && !import_run_stop_requested?(run)
  end

  def import_run_stop_action_label(run)
    run.status == "queued" ? "Abbrechen" : "Stoppen"
  end

  def import_run_stop_path(run, section: nil)
    case run.source_type
    when "merge"
      stop_merge_run_backend_import_sources_path(run_id: run.id, section: section)
    when "easyticket"
      stop_easyticket_run_backend_import_source_path(run.import_source_id, run_id: run.id, section: section)
    when "eventim"
      stop_eventim_run_backend_import_source_path(run.import_source_id, run_id: run.id, section: section)
    when "reservix"
      stop_reservix_run_backend_import_source_path(run.import_source_id, run_id: run.id, section: section)
    when "llm_enrichment"
      stop_llm_enrichment_run_backend_import_sources_path(run_id: run.id, section: section)
    when "llm_genre_grouping"
      stop_llm_genre_grouping_run_backend_import_sources_path(run_id: run.id, section: section)
    end
  end

  def import_run_filtered_label(run)
    return llm_genre_grouping_skipped_count(run) if llm_genre_grouping_import_run?(run)
    return llm_skipped_count(run) if run.source_type == "llm_enrichment"
    return "-" if run.source_type == "merge"

    run.filtered_count
  end

  def import_run_raw_imports_label(run)
    return llm_genre_grouping_selected_count(run) if llm_genre_grouping_import_run?(run)
    return llm_selected_count(run) if run.source_type == "llm_enrichment"
    return merge_import_records_count(run) if run.source_type == "merge"

    run.upserted_count
  end

  def import_run_merge_groups_label(run)
    return "-" if %w[llm_enrichment llm_genre_grouping].include?(run.source_type)
    return "-" unless run.source_type == "merge"

    merge_groups_count(run) || run.imported_count
  end

  def import_run_inserts_label(run)
    return llm_genre_grouping_groups_count(run) if llm_genre_grouping_import_run?(run)
    return llm_enriched_count(run) if run.source_type == "llm_enrichment"
    return run.upserted_count unless run.source_type == "merge"

    metadata = import_run_metadata(run)
    events_created_count = Integer(metadata["events_created_count"], exception: false)
    return events_created_count if events_created_count

    run.imported_count
  end

  def import_run_updates_label(run)
    return "-" if %w[llm_enrichment llm_genre_grouping].include?(run.source_type)
    return "-" unless run.source_type == "merge"

    metadata = import_run_metadata(run)
    Integer(metadata["events_updated_count"], exception: false) || "-"
  end

  def import_run_duplicates_label(run)
    return "-" if %w[llm_enrichment llm_genre_grouping].include?(run.source_type)
    return "-" unless run.source_type == "merge"

    metadata = import_run_metadata(run)
    Integer(metadata["duplicate_matches_count"], exception: false) || 0
  end

  def import_run_collapsed_records_label(run)
    return llm_genre_grouping_requests_count(run) if llm_genre_grouping_import_run?(run)
    return llm_batches_count(run) if run.source_type == "llm_enrichment"
    return "-" unless run.source_type == "merge"

    raw_imports = merge_import_records_count(run)
    groups_count = merge_groups_count(run) || run.imported_count
    return "-" if raw_imports.nil? || groups_count.nil?

    raw_imports - groups_count
  end

  def import_run_column_description(key)
    IMPORT_RUN_COLUMN_DESCRIPTIONS.fetch(key)
  end

  def import_run_single_event_llm?(run)
    llm_import_run?(run) && import_run_metadata(run)["trigger_scope"] == "single_event"
  end

  def import_run_single_event_label(run)
    return unless import_run_single_event_llm?(run)

    event_id = import_run_single_event_id(run)
    return "Einzel-Event" if event_id.blank?

    "Einzel-Event · ##{event_id}"
  end

  def import_run_single_event_context(run)
    return unless import_run_single_event_llm?(run)

    import_run_metadata(run)["target_event_context"].to_s.strip.presence
  end

  def import_run_single_event_id(run)
    Integer(import_run_metadata(run)["target_event_id"], exception: false)
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

  def llm_selected_count(run)
    Integer(import_run_metadata(run)["events_selected_count"], exception: false) || run.fetched_count
  end

  def llm_skipped_count(run)
    Integer(import_run_metadata(run)["events_skipped_count"], exception: false) || run.filtered_count
  end

  def llm_enriched_count(run)
    Integer(import_run_metadata(run)["events_enriched_count"], exception: false) || run.imported_count
  end

  def llm_batches_count(run)
    Integer(import_run_metadata(run)["batches_count"], exception: false) || "-"
  end

  def llm_genre_grouping_selected_count(run)
    Integer(import_run_metadata(run)["genres_selected_count"], exception: false) || run.fetched_count
  end

  def llm_genre_grouping_skipped_count(run)
    Integer(import_run_metadata(run)["genres_skipped_count"], exception: false) || run.filtered_count
  end

  def llm_genre_grouping_groups_count(run)
    Integer(import_run_metadata(run)["groups_created_count"], exception: false) || run.imported_count
  end

  def llm_genre_grouping_requests_count(run)
    Integer(import_run_metadata(run)["requests_count"], exception: false) || run.upserted_count
  end
end
