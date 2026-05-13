module Public::SeoHelper
  HOMEPAGE_SEO_DESCRIPTION = "Konzerte, Shows und Events in Stuttgart und Region entdecken: aktuelle Termine, Highlights, Tickets und News bei Stuttgart Live.".freeze

  def render_public_seo(title:, description:, canonical_url:, meta_title: nil, og_image_url: nil, og_type: "website", robots: nil, json_ld: nil)
    render "public/seo/head",
           presenter: public_seo_presenter(
             title: title,
             description: description,
             canonical_url: canonical_url,
             meta_title: meta_title,
             og_image_url: og_image_url,
             og_type: og_type,
             robots: robots,
             json_ld: json_ld
           )
  end

  def public_seo_presenter(...)
    unless defined?(Public::Seo::PagePresenter)
      presenter_path = Rails.root.join("app/presenters/public/seo/page_presenter.rb").to_s
      require_dependency presenter_path
      load presenter_path unless defined?(Public::Seo::PagePresenter)
    end

    Public::Seo::PagePresenter.new(...)
  end

  def public_homepage_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "@id" => "#{root_url}#website",
      name: "Stuttgart Live",
      url: root_url,
      description: HOMEPAGE_SEO_DESCRIPTION,
      potentialAction: {
        "@type" => "SearchAction",
        target: {
          "@type" => "EntryPoint",
          urlTemplate: "#{root_url.delete_suffix("/")}/search?q={search_term_string}"
        },
        "query-input" => "required name=search_term_string"
      }
    }
  end

  def public_event_item_list_json_ld(events, name:, canonical_url:)
    items = Array(events).compact.uniq(&:id).first(50).each_with_index.map do |event, index|
      {
        "@type" => "ListItem",
        position: index + 1,
        url: event_url(event.slug),
        name: public_event_item_name(event)
      }
    end

    {
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      name: name,
      url: canonical_url,
      itemListElement: items
    }.compact
  end

  def public_homepage_seo_events
    [
      @home_featured_events,
      @home_tagestipp_events,
      @home_highlight_events,
      Array(@home_genre_lanes).flat_map { |lane| lane.respond_to?(:events) ? lane.events : [] }
    ].flatten.compact.uniq(&:id)
  end

  def public_lane_seo_description(lane)
    case lane.key
    when "highlights"
      "Ausgewählte Konzert- und Event-Highlights in Stuttgart und Region mit aktuellen Terminen und Ticketinformationen."
    when "all_stuttgart"
      "Alle aktuellen Veranstaltungen aus Stuttgart: Konzerte, Shows und Events mit Terminen, Locations und Tickets."
    when "tagestipp"
      "Der Tagestipp von Stuttgart Live: ausgewählte Events und Konzerte für heute in Stuttgart und Region."
    else
      "#{lane.title}: aktuelle Konzerte, Shows und Events in Stuttgart und Region entdecken."
    end
  end

  def public_lane_canonical_url(lane)
    path = lane.public_path.presence || genre_lane_path(lane.group.slug)
    "#{root_url.delete_suffix("/")}#{path}"
  end

  def public_static_page_description(page)
    page.intro.to_s.squish.presence ||
      page.body.to_plain_text.squish.presence&.truncate(160) ||
      "#{page.title} bei Stuttgart Live."
  end

  def public_event_item_name(event)
    [ event.artist_name, event.title ].compact_blank.join(" - ").presence || event.slug
  end
end
