module Backend::NewsletterIssuesHelper
  NEWSLETTER_STATUS_LABELS = {
    "draft" => "Entwurf",
    "synced" => "Synchronisiert",
    "tested" => "Getestet",
    "sending" => "Sendet",
    "sent" => "Gesendet",
    "failed" => "Fehler"
  }.freeze

  def newsletter_event_options(events, selected_event: nil)
    (events.to_a + Array(selected_event)).uniq(&:id).map do |event|
      [ newsletter_event_option_label(event), event.id ]
    end
  end

  def newsletter_event_option_label(event)
    title = [
      event.artist_name.to_s.strip.presence,
      event.title.to_s.strip.presence
    ].compact.uniq(&:downcase).join(" - ")
    date = event.start_at.present? ? l(event.start_at.to_date, format: "%d.%m.%Y") : "Termin offen"
    "#{date} - #{title}"
  end

  def newsletter_issue_status_label(issue)
    NEWSLETTER_STATUS_LABELS.fetch(issue.status, issue.status.to_s.humanize)
  end

  def newsletter_issue_status_class(issue)
    "newsletter-issue-list-status-#{issue.status.to_s.dasherize}"
  end
end
