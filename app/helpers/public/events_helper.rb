module Public::EventsHelper
  PUBLIC_SEARCH_PLACEHOLDER_SEQUENCE = [
    { text: "Suche nach Künstlern und Events in Stuttgart", cursor_blinks: 2, hold_ms: 5000, instant: true, repeat: false },
    { text: "Pop", cursor_blinks: 4 },
    { text: "Diesen Freitag im Wizemann", cursor_blinks: 6 },
    { text: "Heute im Goldmark's", cursor_blinks: 0 },
    { text: "Diese Woche in der Porsche-Arena", cursor_blinks: 0 },
    { text: "Rock", cursor_blinks: 2 },
    { text: "Übermorgen im LKA Longhorn", cursor_blinks: 2 },
    { text: "Morgen in der Liederhalle", cursor_blinks: 0 },
    { text: "Theater", cursor_blinks: 4 },
    { text: "Am 12.04. in der Schleyer-Halle", cursor_blinks: 8 },
    { text: "Dieses Wochenende im Club Zentral", cursor_blinks: 4 },
    { text: "Am 12.04.", cursor_blinks: 2 },
    { text: "Nächsten Monat im Theaterhaus", cursor_blinks: 4 },
    { text: "Nächste Woche in der Schleyer-Halle", cursor_blinks: 5 },
    { text: "Im Juni im Kulturquartier", cursor_blinks: 3 },
    { text: "Am Wochenende in der Staatsoper", cursor_blinks: 4 },
    { text: "Im April in der Wagenhallen", cursor_blinks: 3 }
  ].freeze

  PUBLIC_SEARCH_PLACEHOLDER_PHRASES = [
    *PUBLIC_SEARCH_PLACEHOLDER_SEQUENCE.map { |entry| entry.fetch(:text) }
  ].freeze

  EventDetailTextColumns = Data.define(:left, :right)

  def effective_public_event_series_ids(events)
    Public::Events::EffectiveSeriesIdsQuery.call(events)
  end

  def public_event_series_effective?(event, effective_series_ids: nil)
    return false if event.event_series_id.blank?

    Array(effective_series_ids).include?(event.event_series_id)
  end

  def public_event_visibility_badges(event)
    badges = []

    unless event.live?
      badges << {
        label: (event.scheduled? ? "Geplant" : public_event_status_label(event.status)),
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
    when "needs_review" then "Draft"
    when "ready_for_publish" then "Unpublished"
    when "published" then "Published"
    when "rejected" then "Rejected"
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

  def public_event_detail_path(event, browse_state)
    event_path(event.slug, **browse_state.route_params)
  end

  def public_event_series_terms_path(event, browse_state)
    termine_event_path(event.slug, **browse_state.route_params)
  end

  def public_events_index_path(browse_state, page: nil, format: nil)
    route_params = browse_state.route_params(page: page, format: format)
    return search_path(**route_params) if browse_state.search_query_present?

    events_path(**route_params)
  end

  def public_event_show_presenter(event, primary_offer:, browse_state:)
    unless defined?(Public::Events::ShowPresenter)
      presenter_path = Rails.root.join("app/presenters/public/events/show_presenter.rb").to_s
      require_dependency presenter_path
      load presenter_path unless defined?(Public::Events::ShowPresenter)
    end

    Public::Events::ShowPresenter.new(
      event,
      primary_offer: primary_offer,
      browse_state: browse_state,
      view_context: self
    )
  end

  def event_detail_text_columns(text)
    normalized = text.to_s.gsub("\r\n", "\n").strip
    return EventDetailTextColumns.new(left: nil, right: nil) if normalized.blank?

    units, separator = event_detail_text_units(normalized)
    return EventDetailTextColumns.new(left: normalized, right: nil) if units.length <= 1

    split_index = balanced_text_split_index(units)
    left = units.first(split_index).join(separator).strip
    right = units.drop(split_index).join(separator).strip

    EventDetailTextColumns.new(
      left: left.presence || normalized,
      right: right.presence
    )
  end

  def effective_public_grid_variant_for(event, _index)
    editorial_image = editorial_event_image_for(event)
    editorial_image&.grid_variant.presence || EventImage::GRID_VARIANT_1X1
  end

  def card_slot_for_grid_variant(grid_variant)
    case grid_variant.to_s
    when EventImage::GRID_VARIANT_1X1 then :grid_default
    when EventImage::GRID_VARIANT_1X2 then :grid_tall
    when EventImage::GRID_VARIANT_2X1 then :grid_wide
    when EventImage::GRID_VARIANT_2X2 then :grid_large
    else :grid_default
    end
  end

  def event_image_source(image, strict_proxy: false)
    return nil if image.blank?
    return optimized_event_image_source(image, strict_proxy:) if image.is_a?(EventImage)

    image.image_url
  end

  def event_image_alt(image, event)
    default_alt = "#{event.artist_name} - #{event.title}"
    return default_alt unless image.is_a?(EventImage)

    image.alt_text.presence || default_alt
  end

  def public_event_ticket_price(event, offer = event.public_ticket_offer, format: :card)
    return unless offer.present?

    if event.min_price.present? && event.max_price.present? && event.min_price < event.max_price
      min_price = number_to_currency(event.min_price, unit: "€", separator: ",", delimiter: ".", format: "%n%u")
      return "#{min_price} bis #{number_to_currency(event.max_price, unit: "€", separator: ",", delimiter: ".", format: "%n%u")}" if format == :detail

      "ab #{min_price}"
    else
      offer.ticket_price_text.to_s.presence
    end
  end

  private

  def event_detail_text_units(text)
    paragraphs = text.split(/\n{2,}/).map(&:strip).reject(&:blank?)
    return [ paragraphs, "\n\n" ] if paragraphs.length > 1

    lines = text.lines.map(&:strip).reject(&:blank?)
    return [ lines, "\n" ] if lines.length > 2

    sentences = text.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)
    return [ sentences, " " ] if sentences.length > 1

    [ [ text ], "\n\n" ]
  end

  def balanced_text_split_index(units)
    total_length = units.sum { |unit| unit.length }
    running_length = 0

    units.each_with_index do |unit, index|
      next if index.zero?

      running_length += units[index - 1].length
      return index if running_length >= (total_length / 2.0)
    end

    1
  end

  def public_frontend_visible?(event)
    event.live?
  end

  def editorial_event_image_for(event)
    images = event.event_images

    if images.loaded?
      images.find { |image| image.is_a?(EventImage) && image.detail_hero? }
    else
      images.detail_hero.ordered.first
    end
  end
end
