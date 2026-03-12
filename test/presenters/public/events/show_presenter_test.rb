require "test_helper"
require "ostruct"

class Public::Events::ShowPresenterTest < ActiveSupport::TestCase
  class FakeGenres
    def initialize(names)
      @names = names
    end

    def order(*)
      self
    end

    def pluck(*)
      @names
    end
  end

  class ViewContextStub
    def event_image_source(image)
      image&.image_url || image&.source
    end

    def event_image_alt(image, event)
      image&.alt.presence || "#{event.artist_name} - #{event.title}"
    end

    def event_detail_image_style(image)
      image&.style
    end

    def public_event_visibility_badges(_event)
      [ { label: "Published", css_class: "status-badge-published" } ]
    end

    def public_events_index_path(_browse_state)
      "/events"
    end

    def event_source_label(source)
      source.to_s
    end

    def l(value, format:)
      value.strftime(format)
    end

    def rails_storage_proxy_url(file)
      "https://cdn.example.test/#{file}"
    end

    def event_url(slug)
      "https://stuttgart-live.de/events/#{slug}"
    end
  end

  test "exposes hero, meta and navigation data" do
    event = build_event(
      artist_name: "Band",
      title: "Live",
      event_info: "A" * 200,
      start_at: Time.zone.local(2026, 6, 17, 20, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      slug: "band-live",
      primary_source: "eventim"
    )

    presenter = build_presenter(event)

    assert_equal "Band - Live | Stuttgart Live", presenter.page_title
    assert_equal "Band - Live", presenter.meta_title
    assert_equal event.event_info.truncate(160), presenter.meta_description
    assert_equal "https://cdn.example.test/social.jpg", presenter.og_image_url
    assert_equal "https://stuttgart-live.de/events/band-live", presenter.canonical_url
    assert_equal "/events", presenter.back_path
    assert_equal "eventim", presenter.primary_source_label
    assert_equal "event-detail-header event-detail-header-with-image", presenter.header_classes
    assert_equal "/hero-desktop.jpg", presenter.hero_desktop_image_source
    assert_equal "/hero-mobile.jpg", presenter.hero_mobile_image_source
    assert_equal "Band", presenter.hero_alt_text
    assert_equal "object-position: center;", presenter.hero_image_style
    assert_equal "Bildquelle: Easy Ticket Service / Veranstalter", presenter.hero_image_credit
    assert_equal [ "Mittwoch", "17.06.2026", "Im Wizemann, Stuttgart" ], presenter.primary_meta
    assert_equal "Beginn: 20:00 Uhr · Einlass: 19:00 Uhr", presenter.schedule_line
    assert_equal [ { label: "Published", css_class: "status-badge-published" } ], presenter.visibility_badges
  end

  test "collects cta, links, genres and slider items" do
    event = build_event(
      artist_name: "Band",
      title: "Live",
      start_at: Time.zone.local(2026, 6, 17, 20, 0),
      badge_text: "Fast ausverkauft",
      homepage_url: "https://band.example",
      instagram_url: "https://instagram.example/band",
      facebook_url: "",
      youtube_url: "https://www.youtube.com/watch?v=demo"
    )
    primary_offer = OpenStruct.new(
      resolved_ticket_url: "https://tickets.example/band",
      ticket_price_text: "39,00 €"
    )

    presenter = build_presenter(event, primary_offer: primary_offer)

    assert presenter.show_ticket_cta?
    assert_equal "Fast ausverkauft", presenter.ticket_badge_text
    assert_equal "https://tickets.example/band", presenter.ticket_url
    assert_equal "39,00 €", presenter.ticket_price_text
    assert_equal [ "Pop", "Rock" ], presenter.genres
    assert_equal [ "Homepage", "Instagram" ], presenter.social_links.map(&:label)
    assert_equal [ "https://band.example", "https://instagram.example/band" ], presenter.social_links.map(&:url)
    assert_equal "https://www.youtube.com/embed/demo", presenter.youtube_embed_url
    assert_nil presenter.hero_image_credit
    assert_equal 1, presenter.slider_items.size
    assert_equal "/slide-1.jpg", presenter.slider_items.first.source
    assert_equal "Slide 1 Alt", presenter.slider_items.first.alt_text
    assert_equal "Live auf der Bühne", presenter.slider_items.first.caption
  end

  private

  def build_presenter(event, primary_offer: nil)
    Public::Events::ShowPresenter.new(
      event,
      primary_offer: primary_offer,
      browse_state: Object.new,
      view_context: ViewContextStub.new
    )
  end

  test "uses editorial hero sub text as copyright credit" do
    event = build_event(
      artist_name: "Band",
      title: "Live",
      start_at: Time.zone.local(2026, 6, 17, 20, 0)
    )

    hero_image = EventImage.new(purpose: EventImage::PURPOSE_DETAIL_HERO, sub_text: "Foto Max Mustermann")
    event.define_singleton_method(:image_for) do |slot:, breakpoint:|
      case [ slot, breakpoint ]
      when [ :detail_hero, :desktop ], [ :grid_default, :mobile ]
        hero_image
      when [ :social_card, :desktop ]
        OpenStruct.new(image_url: "https://cdn.example.test/social.jpg")
      end
    end

    presenter = build_presenter(event)

    assert_equal "Band", presenter.hero_alt_text
    assert_equal "© Foto Max Mustermann", presenter.hero_image_credit
  end

  def build_event(**attributes)
    event = Event.new(attributes)

    event.define_singleton_method(:image_for) do |slot:, breakpoint:|
      case [ slot, breakpoint ]
      when [ :social_card, :desktop ]
        OpenStruct.new(image_url: "https://cdn.example.test/social.jpg")
      when [ :detail_hero, :desktop ]
        OpenStruct.new(source: "easyticket", image_url: "/hero-desktop.jpg", alt: "Hero Alt", style: "object-position: center;")
      when [ :grid_default, :mobile ]
        OpenStruct.new(source: "easyticket", image_url: "/hero-mobile.jpg", alt: "Hero Mobile Alt")
      end
    end

    event.define_singleton_method(:slider_images) do
      [
        OpenStruct.new(source: "/slide-1.jpg", alt: "Slide 1 Alt", sub_text: "Live auf der Bühne"),
        OpenStruct.new(source: nil, alt: "Ohne Bild", sub_text: "Wird ignoriert")
      ]
    end

    event.define_singleton_method(:genres) do
      FakeGenres.new([ "Pop", "Rock" ])
    end

    event
  end
end
