module Backend::EventsHelper
  def event_display_organizer_name(event)
    organizer_name = event.organizer_name.to_s.strip
    return organizer_name if organizer_name.present?

    event_source_payloads(event).each do |source|
      case source[:source]
      when "easyticket"
        attributes =
          Importing::Easyticket::PayloadProjection.new(
            dump_payload: source[:dump_payload],
            detail_payload: source[:detail_payload]
          ).to_attributes
        candidate = attributes&.dig(:organizer_name).to_s.strip
        return candidate if candidate.present?
      when "eventim"
        attributes = Importing::Eventim::PayloadProjection.new(feed_payload: source[:dump_payload]).to_attributes
        candidate = attributes&.dig(:organizer_name).to_s.strip
        return candidate if candidate.present?
      end
    end

    nil
  end

  def event_display_promoter_id(event)
    promoter_id = event.promoter_id.to_s.strip
    return promoter_id if promoter_id.present?

    event_source_payloads(event).each do |source|
      next unless source[:source] == "eventim"

      attributes = Importing::Eventim::PayloadProjection.new(feed_payload: source[:dump_payload]).to_attributes
      candidate = attributes&.dig(:promoter_id).to_s.strip
      return candidate if candidate.present?
    end

    nil
  end

  def event_source_payloads(event)
    sources = event.source_snapshot.is_a?(Hash) ? Array(event.source_snapshot["sources"]) : []

    sources.filter_map do |source|
      next unless source.is_a?(Hash)

      raw_payload = source["raw_payload"]
      next unless raw_payload.is_a?(Hash)

      {
        source: source["source"].to_s.presence || "unbekannt",
        external_event_id: source["external_event_id"].to_s.presence,
        dump_payload: raw_payload["dump_payload"] || {},
        detail_payload: raw_payload["detail_payload"] || {}
      }
    end
  end

  def pretty_json_payload(value)
    parsed = if value.is_a?(String)
      JSON.parse(value)
    else
      value
    end

    JSON.pretty_generate(parsed)
  rescue JSON::ParserError, JSON::GeneratorError
    value.to_s
  end

  def event_status_label(status)
    case status.to_s
    when "imported" then "importiert"
    when "needs_review" then "Review"
    when "ready_for_publish" then "bereit"
    when "published" then "publiziert"
    when "rejected" then "abgelehnt"
    else status.to_s
    end
  end

  def event_status_select_label(status)
    label = status.to_s == "ready_for_publish" ? "depubliziert" : event_status_label(status)
    label.upcase
  end

  def event_status_badge_class(status)
    case status.to_s
    when "published"
      "status-badge status-badge-published"
    when "ready_for_publish"
      "status-badge status-badge-ready"
    when "needs_review"
      "status-badge status-badge-review"
    when "rejected"
      "status-badge status-badge-rejected"
    else
      "status-badge status-badge-default"
    end
  end

  def event_import_change_badge(event, merge_run_id:)
    merge_run_id_value = merge_run_id.to_i
    return nil if merge_run_id_value <= 0

    actions = import_change_actions_for(event, merge_run_id_value)
    return nil if actions.empty?

    if actions.include?("merged_create")
      { label: "Neu (Import)", css_class: "status-badge status-badge-import-new" }
    else
      { label: "Aktualisiert (Import)", css_class: "status-badge status-badge-import-updated" }
    end
  end

  private

  def import_change_actions_for(event, merge_run_id)
    association = event.event_change_logs

    if association.loaded?
      association.filter_map do |change_log|
        next unless [ "merged_create", "merged_update" ].include?(change_log.action.to_s)
        next unless change_log_merge_run_id(change_log) == merge_run_id

        change_log.action.to_s
      end.uniq
    else
      association
        .where(action: [ "merged_create", "merged_update" ])
        .where("metadata ->> 'merge_run_id' = ?", merge_run_id.to_s)
        .pluck(:action)
        .uniq
    end
  end

  def change_log_merge_run_id(change_log)
    metadata = change_log.metadata.is_a?(Hash) ? change_log.metadata.deep_stringify_keys : {}
    Integer(metadata["merge_run_id"], exception: false)
  end
end
