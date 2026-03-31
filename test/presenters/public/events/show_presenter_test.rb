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

    def public_event_visibility_badges(_event)
      [ { label: "Published", css_class: "status-badge-published" } ]
    end

    def root_path
      "/"
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

    def optimized_event_image_url(image)
      "https://cdn.example.test/optimized/#{image.object_id}"
    end

    def presenter_logo_source(presenter, size: :detail)
      "/rails/active_storage/presenters/#{presenter.id}-#{size}"
    end

    def venue_logo_source(venue, size: :detail)
      "/rails/active_storage/venues/#{venue.id || 'new'}-#{size}"
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

    assert_equal "Band – Live | 17.06.2026 | Im Wizemann, Stuttgart | Stuttgart Live", presenter.page_title
    assert_equal "Band – Live | 17.06.2026 | Im Wizemann, Stuttgart", presenter.meta_title
    assert_equal event.event_info.truncate(160), presenter.meta_description
    assert_equal "https://cdn.example.test/social.jpg", presenter.og_image_url
    assert_equal "https://stuttgart-live.de/events/band-live", presenter.canonical_url
    assert_equal "/", presenter.back_path
    assert_equal "eventim", presenter.primary_source_label
    assert_equal "event-detail-header event-detail-header-with-image", presenter.header_classes
    assert_equal "/hero-desktop.jpg", presenter.hero_desktop_image_source
    assert_equal "/hero-mobile.jpg", presenter.hero_mobile_image_source
    assert_equal "Band", presenter.hero_alt_text
    assert_equal "Bildquelle: Easy Ticket Service / Veranstalter", presenter.hero_image_credit
    assert_equal [ "Datum", "Beginn", "Ort" ], presenter.fact_items.map(&:label)
    assert_equal [ "Mittwoch, 17.06.2026", "20:00 Uhr", "Im Wizemann, Stuttgart" ], presenter.fact_items.map(&:value)
    assert_nil presenter.schedule_line
    assert_equal [ { label: "Published", css_class: "status-badge-published" } ], presenter.visibility_badges
  end

  test "collects cta, links, genres and hero gallery items" do
    event = build_event(
      artist_name: "Band",
      title: "Live",
      start_at: Time.zone.local(2026, 6, 17, 20, 0),
      badge_text: "Fast ausverkauft",
      support: "Special Guest",
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

    assert presenter.show_ticket_panel?
    assert presenter.show_ticket_link?
    assert_not presenter.show_sks_sold_out_message?
    assert_equal "Fast ausverkauft", presenter.ticket_badge_text
    assert_equal "https://tickets.example/band", presenter.ticket_url
    assert_equal "39,00 €", presenter.ticket_price_text
    assert_equal [ "Pop", "Rock" ], presenter.genres
    assert_equal [ "Pop", "Rock" ], presenter.genre_tags
    assert_equal [ "Homepage", "Instagram" ], presenter.external_links.map(&:label)
    assert_equal [ "https://band.example", "https://instagram.example/band" ], presenter.external_links.map(&:url)
    assert_equal "https://www.youtube.com/embed/demo", presenter.youtube_embed_url
    assert_equal "Special Guest", presenter.support_text
    assert presenter.has_media_block?
    assert presenter.has_secondary_content?
    assert_equal 1, presenter.slider_items.size
    assert_equal "/slide-1.jpg", presenter.slider_items.first.source
    assert_equal "Slide 1 Alt", presenter.slider_items.first.alt_text
    assert_equal "Live auf der Bühne", presenter.slider_items.first.caption
    assert_equal 2, presenter.hero_gallery_slides.size
    assert presenter.hero_gallery_rotates?
    assert_equal "/hero-desktop.jpg", presenter.hero_gallery_slides.first.desktop_source
    assert_equal "/hero-mobile.jpg", presenter.hero_gallery_slides.first.mobile_source
    assert_equal "Bildquelle: Easy Ticket Service / Veranstalter", presenter.hero_gallery_slides.first.credit
    assert_equal "/slide-1.jpg", presenter.hero_gallery_slides.second.desktop_source
    assert_equal "Live auf der Bühne", presenter.hero_gallery_slides.second.caption
  end

  test "hides ticket cta for past events" do
    event = build_event(
      artist_name: "Band",
      title: "Live",
      start_at: 2.hours.ago
    )
    primary_offer = OpenStruct.new(
      resolved_ticket_url: "https://tickets.example/band",
      ticket_price_text: "39,00 €"
    )

    presenter = build_presenter(event, primary_offer: primary_offer)

    assert_not presenter.show_ticket_panel?
    assert_nil presenter.ticket_url
    assert_nil presenter.ticket_price_text
  end

  test "shows sks sold out message without ticket link for sold out sks events" do
    event = build_event(
      artist_name: "Band",
      title: "Live",
      start_at: Time.zone.local(2026, 6, 17, 20, 0),
      promoter_id: AppSetting.sks_promoter_ids.first,
      sks_sold_out_message: "Bitte beim Veranstalter nach Restkarten fragen"
    )
    event.define_singleton_method(:public_sold_out?) { true }
    event.define_singleton_method(:sks_promoter?) { true }

    presenter = build_presenter(event, primary_offer: nil)

    assert presenter.show_ticket_panel?
    assert_not presenter.show_ticket_link?
    assert presenter.show_sks_sold_out_message?
    assert_equal "Bitte beim Veranstalter nach Restkarten fragen", presenter.sks_sold_out_message
    assert_nil presenter.ticket_url
    assert_nil presenter.ticket_price_text
  end

  test "exposes hero stage aspect ratio for editorial hero images" do
    event = build_event(artist_name: "Band", title: "Live")
    hero_image = EventImage.new(purpose: EventImage::PURPOSE_DETAIL_HERO)
    hero_image.define_singleton_method(:file) do
      OpenStruct.new(
        attached?: true,
        blob: OpenStruct.new(metadata: { "width" => 1200, "height" => 900 })
      )
    end

    event.define_singleton_method(:image_for) do |slot:, breakpoint:|
      case [ slot, breakpoint ]
      when [ :detail_hero, :desktop ]
        hero_image
      when [ :grid_default, :mobile ]
        OpenStruct.new(source: "easyticket", image_url: "/hero-mobile.jpg", alt: "Hero Mobile Alt")
      when [ :social_card, :desktop ]
        OpenStruct.new(image_url: "https://cdn.example.test/social.jpg")
      end
    end

    presenter = build_presenter(event)

    assert_equal "1200 / 900", presenter.hero_stage_aspect_ratio
    assert_equal "42.6667rem", presenter.hero_stage_max_width
  end

  test "exposes presenter logo source urls" do
    event = build_event(artist_name: "Band", title: "Live")
    presenter_record = Presenter.new(name: "SVG Presenter")
    presenter_record.id = 123
    presenter_record.logo.attach(create_svg_blob(filename: "presenter.svg"))
    event.define_singleton_method(:ordered_presenters) { [ presenter_record ] }

    presenter = build_presenter(event)

    assert_equal [ "/rails/active_storage/presenters/123-detail" ], presenter.presenters.map(&:logo_source)
  end

  test "uses llm enrichment as fallback for detail content" do
    event = build_event(
      artist_name: "Band",
      title: "",
      event_info: "",
      homepage_url: "",
      instagram_url: "",
      facebook_url: "",
      youtube_url: "",
      venue: "Im Wizemann"
    )

    event.build_llm_enrichment(
      event_description: "LLM Event- und Artist-Beschreibung",
      venue_description: "LLM Venue Beschreibung",
      homepage_link: "https://llm-homepage.example",
      instagram_link: "https://instagram.example/llm-band",
      facebook_link: "https://facebook.example/llm-band",
      youtube_link: "https://www.youtube.com/watch?v=fallback",
      genre: [ "Indie", "Rock" ],
      model: "gpt-test",
      prompt_version: "v1",
      raw_response: {}
    )
    event.venue_record.description = "Venue Modell Beschreibung"

    presenter = build_presenter(event)

    assert_nil presenter.display_title
    assert_equal "Band", presenter.display_headline
    assert_equal "LLM Event- und Artist-Beschreibung", presenter.primary_description
    assert_equal "Venue Modell Beschreibung", presenter.venue_description
    assert_equal [ "Homepage", "Instagram", "Facebook" ], presenter.external_links.map(&:label)
    assert_equal [ "https://llm-homepage.example", "https://instagram.example/llm-band", "https://facebook.example/llm-band" ], presenter.external_links.map(&:url)
    assert_equal "https://www.youtube.com/embed/fallback", presenter.youtube_embed_url
    assert_equal [ "Pop", "Rock", "Indie" ], presenter.genre_tags
    assert_equal [ "Indie", "Rock" ], presenter.enrichment_genres
    assert_equal "Im Wizemann", presenter.venue_info.name
  end

  test "adds youtube fallback link when url is not embeddable" do
    event = build_event(
      artist_name: "Band",
      title: "Live",
      youtube_url: "https://www.youtube.com/@BandChannel"
    )
    event.define_singleton_method(:slider_images) { [] }

    presenter = build_presenter(event)

    assert_nil presenter.youtube_embed_url
    assert_equal [ "YouTube" ], presenter.external_links.map(&:label)
    assert_equal "https://www.youtube.com/@BandChannel", presenter.external_links.first.url
    assert_not presenter.has_media_block?
  end

  test "builds static hero gallery when no slider images exist" do
    event = build_event(artist_name: "Band", title: "Live")
    event.define_singleton_method(:slider_images) { [] }

    presenter = build_presenter(event)

    assert_equal 1, presenter.hero_gallery_slides.size
    assert_not presenter.hero_gallery_rotates?
    assert_equal "/hero-desktop.jpg", presenter.hero_gallery_slides.first.desktop_source
  end

  test "hides duplicate title lines and deduplicates repeated paragraphs" do
    event = build_event(
      artist_name: "Kuult",
      title: "Kuult",
      event_info: "Fallschirmvertrauen - Tour 2026\n\nFallschirmvertrauen - Tour 2026"
    )

    presenter = build_presenter(event)

    assert_equal "Kuult", presenter.display_headline
    assert_equal "Kuult", presenter.display_title
    assert_not presenter.show_distinct_title?
    assert_equal "Fallschirmvertrauen - Tour 2026", presenter.primary_description
  end

  test "does not duplicate city when venue already includes it" do
    event = build_event(
      artist_name: "Band",
      title: "Live",
      venue: "Im Wizemann (Halle) Stuttgart",
      city: "Stuttgart"
    )

    presenter = build_presenter(event)

    assert_equal "Im Wizemann (Halle) Stuttgart", presenter.send(:venue_location)
  end

  test "uses loaded genres without extra queries" do
    event = events(:published_one)
    loaded_event = Event.includes(:genres).find(event.id)
    presenter = Public::Events::ShowPresenter.new(
      loaded_event,
      primary_offer: nil,
      browse_state: Object.new,
      view_context: ViewContextStub.new
    )

    queries = capture_sql_queries { assert_equal [ "Rock" ], presenter.genres }

    assert_equal 0, queries
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

  test "uses source-specific default credit for import images" do
    {
      "easyticket" => "Bildquelle: Easy Ticket Service / Veranstalter",
      "eventim" => "Bildquelle: Eventim / Veranstalter",
      "reservix" => "Bildquelle: Reservix / Veranstalter"
    }.each do |source, expected_credit|
      event = build_event(artist_name: "Band", title: "Live")

      event.define_singleton_method(:image_for) do |slot:, breakpoint:|
        case [ slot, breakpoint ]
        when [ :social_card, :desktop ]
          OpenStruct.new(image_url: "https://cdn.example.test/social.jpg")
        when [ :detail_hero, :desktop ], [ :grid_default, :mobile ]
          OpenStruct.new(source: source, image_url: "/hero.jpg", alt: "Hero Alt")
        end
      end

      presenter = build_presenter(event)

      assert_equal expected_credit, presenter.hero_image_credit
    end
  end

  def build_event(**attributes)
    event = Event.new(attributes)

    event.define_singleton_method(:image_for) do |slot:, breakpoint:|
      case [ slot, breakpoint ]
      when [ :social_card, :desktop ]
        OpenStruct.new(image_url: "https://cdn.example.test/social.jpg")
      when [ :detail_hero, :desktop ]
        OpenStruct.new(source: "easyticket", image_url: "/hero-desktop.jpg", alt: "Hero Alt")
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

  def capture_sql_queries
    queries = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if payload[:cached]
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/)

      queries += 1
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries
  end

  def create_svg_blob(filename:)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(<<~SVG),
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <rect width="16" height="16" fill="#000"/>
        </svg>
      SVG
      filename:,
      content_type: "image/svg+xml"
    )
  end
end
