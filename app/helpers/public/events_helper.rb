module Public::EventsHelper
  def public_event_visibility_badges(event)
    badges = []

    unless event.published? && event.published_at.present? && event.published_at <= Time.current
      badges << {
        label: public_event_status_label(event.status),
        css_class: public_event_status_badge_class(event.status)
      }
    end

    if event.start_at.present? && event.start_at < Time.zone.today.beginning_of_day
      badges << {
        label: "Vergangen",
        css_class: "status-badge-default"
      }
    end

    badges
  end

  def event_source_label(source)
    case source.to_s
    when "easyticket" then "easyticket"
    when "eventim" then "eventim"
    else source.to_s
    end
  end

  def public_event_status_options
    Event::STATUSES.reject { |status| status == "imported" }.map do |status|
      [ public_event_status_label(status), status ]
    end
  end

  def public_event_status_label(status)
    case status.to_s
    when "needs_review" then "Review"
    when "ready_for_publish" then "Bereit"
    when "published" then "Publiziert"
    when "rejected" then "Abgelehnt"
    else status.to_s
    end
  end

  def public_event_status_badge_class(status)
    case status.to_s
    when "published" then "status-badge-published"
    when "ready_for_publish" then "status-badge-ready"
    when "needs_review" then "status-badge-review"
    when "rejected" then "status-badge-rejected"
    else "status-badge-default"
    end
  end
end
