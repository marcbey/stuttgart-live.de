module Backend::NewsletterIssuesHelper
  NEWSLETTER_STATUS_LABELS = {
    "draft" => "Entwurf",
    "synced" => "Synchronisiert",
    "tested" => "Getestet",
    "sending" => "Sendet",
    "sent" => "Gesendet",
    "failed" => "Fehler"
  }.freeze

  def newsletter_event_option_label(event)
    [
      event.artist_name.to_s.strip.presence,
      event.title.to_s.strip.presence
    ].compact.uniq(&:downcase).join(" - ")
  end

  def newsletter_issue_status_label(issue)
    NEWSLETTER_STATUS_LABELS.fetch(issue.status, issue.status.to_s.humanize)
  end

  def newsletter_issue_status_class(issue)
    "newsletter-issue-list-status-#{issue.status.to_s.dasherize}"
  end
end
