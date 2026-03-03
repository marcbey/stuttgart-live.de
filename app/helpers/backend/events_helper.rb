module Backend::EventsHelper
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
