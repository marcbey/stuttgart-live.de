module Public::EventsHelper
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
end
