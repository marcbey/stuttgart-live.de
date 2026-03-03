module Backend::EventsHelper
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
end
