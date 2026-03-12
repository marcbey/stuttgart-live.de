module Public::EventsHelper
  PUBLIC_EVENT_GENRE_TILES = [
    [ "Pop", "genre-tile-pop" ],
    [ "Rock", "genre-tile-rock" ],
    [ "Hiphop", "genre-tile-hiphop" ],
    [ "Rap", "genre-tile-rap" ],
    [ "Metal", "genre-tile-metal" ],
    [ "Elektro", "genre-tile-elektro" ],
    [ "Show", "genre-tile-show" ],
    [ "Punk", "genre-tile-punk" ],
    [ "Schlager", "genre-tile-schlager" ]
  ].freeze

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

  def public_event_detail_path(event, browse_state, view: browse_state.view)
    event_path(event.slug, **browse_state.route_params(view: view))
  end

  def public_events_index_path(browse_state, page: nil, view: browse_state.view, format: nil)
    events_path(**browse_state.route_params(page: page, view: view, format: format))
  end

  def public_event_genre_tiles
    PUBLIC_EVENT_GENRE_TILES
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

  def event_image_source(image)
    return nil if image.blank?
    return rails_storage_proxy_path(image.file, only_path: true) if image.is_a?(EventImage)

    image.image_url
  end

  def event_image_alt(image, event)
    default_alt = "#{event.artist_name} - #{event.title}"
    return default_alt unless image.is_a?(EventImage)

    image.alt_text.presence || default_alt
  end
  private

  def editorial_event_image_for(event)
    images = event.event_images

    if images.loaded?
      images.find { |image| image.is_a?(EventImage) && image.detail_hero? }
    else
      images.detail_hero.ordered.first
    end
  end
end
