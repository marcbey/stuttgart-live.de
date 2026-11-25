module Public::SavedEventsHelper
  def saved_events_share_title(events)
    return "Meine Eventauswahl | STUTTGART LIVE" if events.empty?

    "#{events.size} #{events.one? ? 'Event' : 'Events'} für dich | STUTTGART LIVE"
  end

  def saved_events_share_description(events)
    return "Entdecke die geteilte Eventauswahl bei STUTTGART LIVE." if events.empty?

    # Keep all three names and dates plus the remainder within the SEO presenter's 160 characters.
    summary = events.first(3).map do |event|
      name = (event.artist_name.presence || event.title).to_s.squish.truncate(28)
      [ name, event.start_at && l(event.start_at.to_date, format: "%d.%m.%Y") ].compact_blank.join(" · ")
    end.join("; ")
    remaining = events.size - 3
    remaining.positive? ? "#{summary} … und #{remaining} #{remaining == 1 ? 'weiteres Event' : 'weitere Events'}." : summary
  end

  def saved_event_share_text(event)
    venue = event.venue.presence || event.city.presence
    [
      (event.artist_name.presence || event.title).to_s.squish,
      event.start_at && "Datum: #{l(event.start_at.to_date, format: '%d.%m.%Y')}",
      venue.present? && "Ort: #{venue.squish}"
    ].compact_blank.join("\n")
  end

  def saved_events_share_image_url(events)
    events.each do |event|
      image = event.image_for(slot: :social_card, breakpoint: :desktop)
      url = optimized_event_image_url(image)
      return url if url.present?
    end

    image_url("/icon.png")
  end
end
