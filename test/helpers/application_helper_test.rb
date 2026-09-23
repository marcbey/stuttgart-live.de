require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "public design navigation genres do not depend on homepage genre lanes" do
    lanes = public_design_navigation_lanes([], highlight_events: [])

    assert_equal %w[pop-indie-singer-songwriter rock-alternative metal-punk-hardcore hip-hop-r-n-b electronic-music-edm],
                 lanes.map { |lane| lane.group.slug }
    assert_equal "/pop-indie-singer-songwriter", lanes.first.public_path
  end

  test "public homepage header genres do not depend on homepage genre lanes" do
    genres = public_homepage_header_genres

    assert_equal %w[POP ROCK PUNK\ &\ METAL HIP-HOP ELECTRONIC JAZZ KLASSIK THEATER], genres.pluck(:label)
  end

  test "public media path falls back to rails storage proxy when media proxy is disabled" do
    blob = create_uploaded_blob(filename: "fallback.png")

    with_media_proxy(enabled: false) do
      assert_equal rails_storage_proxy_path(blob, only_path: true), public_media_path(blob)
    end
  end

  test "public media path uses signed media paths when media proxy is enabled" do
    blob = create_uploaded_blob(filename: "proxy.png")

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        assert_equal PublicMediaUrl.path_for(blob), public_media_path(blob)
      end
    end
  end

  test "public media path skips rails storage fallback when strict proxy is enabled" do
    blob = create_uploaded_blob(filename: "strict-proxy.png")

    with_media_proxy(enabled: false) do
      assert_nil public_media_path(blob, strict_proxy: true)
    end
  end

  test "homepage media strict proxy follows media proxy availability" do
    with_media_proxy(enabled: false) do
      assert_equal false, homepage_media_strict_proxy?
    end

    with_media_proxy do
      assert homepage_media_strict_proxy?
    end
  end

  test "asset availability checks propshaft load path for fonts" do
    assert asset_available?("archivo-narrow-400.woff2")
  end

  test "public frontend stylesheet keeps accessible search and saved lane styles" do
    stylesheet = Rails.root.join("app/assets/stylesheets/frontend.tailwind.css").read
    saved_lane_rules = stylesheet[/\.lane-header--saved-events\s*\{([^}]*)\}/m, 1]
    public_search_icon_rules = stylesheet.scan(/body\.page-public-events-index \.public-search-icon\s*\{([^}]*)\}/m).flatten
    base_public_search_icon_rules = stylesheet.scan(/\.public-search-icon\s*\{([^}]*)\}/m).flatten

    assert_includes saved_lane_rules, "--lane-header-title-color: #0a2324;"
    assert public_search_icon_rules.any? { |rule| rule.include?("width: 2.5rem;") }
    assert public_search_icon_rules.any? { |rule| rule.include?("height: 2.5rem;") }
    assert base_public_search_icon_rules.any? { |rule| rule.include?("width: 2.5rem;") }
    assert base_public_search_icon_rules.any? { |rule| rule.include?("height: 2.5rem;") }
  end

  test "public search controller keeps aria expanded off the native search input" do
    controller = Rails.root.join("app/javascript/controllers/public_search_controller.js").read

    refute_includes controller, 'inputTarget.setAttribute("aria-expanded"'
  end

  test "public javascript entry lazy loads optional controllers" do
    entrypoint = Rails.root.join("app/javascript/controllers/public_index.js").read
    package_json = Rails.root.join("package.json").read

    assert_includes entrypoint, '"homepage-lane": () => import("./homepage_lane_controller")'
    assert_includes entrypoint, '"partner-strip": () => import("./partner_strip_controller")'
    assert_includes entrypoint, 'document.addEventListener("turbo:load", loadLazyControllers)'
    refute_includes entrypoint, 'import HomepageLaneController from "./homepage_lane_controller"'
    refute_includes entrypoint, 'import PartnerStripController from "./partner_strip_controller"'
    assert_includes package_json, "--chunk-names=[name]-[hash].digested"
  end

  test "promotion banner images use the editor crop ratio in design preview feature slider" do
    partial = Rails.root.join("app/views/public/events/_design_preview_banner_card.html.erb").read

    assert_includes partial, "event_promotion_banner_image_style(event, frame_ratio: 1.0 / 1.16)"
    assert_includes partial, "blog_post_image_style(blog_post, :promotion_banner_image)"
    refute_includes partial, "event_promotion_banner_card_image_style(event)"
    refute_includes partial, "event_promotion_banner_image_style(event, frame_ratio: 16.0 / 9.0)"
  end

  test "local font face stylesheet skips unavailable fonts" do
    original_method = method(:asset_available?)

    singleton_class.define_method(:asset_available?) do |logical_path|
      logical_path != "archivo-narrow-400.woff2"
    end

    stylesheet = local_font_face_stylesheet(frontend: false)

    refute_includes stylesheet, "archivo-narrow-400"
    assert_includes stylesheet, "archivo-narrow-700"
    assert_includes stylesheet, "oswald-300"
  ensure
    singleton_class.define_method(:asset_available?, original_method)
  end

  test "formatted venue address breaks lines at commas" do
    fragment = Nokogiri::HTML.fragment(
      formatted_venue_address("Hanns-Martin-Schleyer-Halle, Mercedesstraße 69, 70372 Stuttgart, Deutschland")
    )

    assert_equal [
      "Hanns-Martin-Schleyer-Halle,",
      "Mercedesstraße 69,",
      "70372 Stuttgart, Deutschland"
    ], fragment.css(".event-detail-venue-address-line").map(&:text)
  end

  test "formatted design preview venue address omits duplicated venue name" do
    fragment = Nokogiri::HTML.fragment(
      formatted_design_preview_venue_address(
        "Porsche-Arena, Mercedesstraße 69, 70372 Stuttgart, Deutschland",
        venue_name: "Porsche-Arena"
      )
    )

    assert_equal [
      "Mercedesstraße 69,",
      "70372 Stuttgart, Deutschland"
    ], fragment.css(".event-detail-venue-address-line").map(&:text)
  end

  test "formatted venue description preserves sanitized rich text links" do
    fragment = Nokogiri::HTML.fragment(
      formatted_venue_description(
        '<div>Infos <strong>unter</strong> <a href="https://venue.example/programm">Programm</a>.</div><script>alert("x")</script>'
      )
    )

    link = fragment.at_css("a.event-detail-inline-link")

    assert_equal "Infos unter Programm.", fragment.text.squish
    assert_equal "https://venue.example/programm", link["href"]
    assert_equal "_blank", link["target"]
    assert_equal "noopener", link["rel"]
    assert_equal "unter", fragment.at_css("strong").text
    assert_empty fragment.css("script")
  end

  test "formatted venue description preserves sanitized rich text images" do
    fragment = Nokogiri::HTML.fragment(
      formatted_venue_description(
        '<div>Intro</div><figure class="attachment"><img src="/rails/active_storage/blobs/proxy/signed/photo.jpg" alt="Bühne" width="1200" height="800" style="width:999px" onerror="alert(1)"></figure>'
      )
    )

    image = fragment.at_css("figure.attachment img")

    assert_equal "/rails/active_storage/blobs/proxy/signed/photo.jpg", image["src"]
    assert_equal "Bühne", image["alt"]
    assert_equal "1200", image["width"]
    assert_equal "800", image["height"]
    assert_nil image["style"]
    assert_nil image["onerror"]
  end

  test "formatted venue description preserves rich text headings" do
    fragment = Nokogiri::HTML.fragment(
      formatted_venue_description(
        "<h3>Ticketoptionen</h3><h4>Flying-High Upgrade | Cirque du Soleil - OVO</h4><p>Infos.</p>"
      )
    )

    assert_equal "Ticketoptionen", fragment.at_css("h3")&.text
    assert_equal "Flying-High Upgrade | Cirque du Soleil - OVO", fragment.at_css("h4")&.text
    assert_equal "Infos.", fragment.at_css("p")&.text
  end

  test "formatted venue description preserves linked rich text images" do
    fragment = Nokogiri::HTML.fragment(
      formatted_venue_description(
        '<a href="https://ticket.example/event" onclick="alert(1)"><figure class="attachment"><img src="/rails/active_storage/blobs/proxy/signed/photo.jpg" alt="Bühne"></figure></a>'
      )
    )

    link = fragment.at_css("a.event-detail-image-link")
    image = link.at_css("figure.attachment img")

    assert_equal "https://ticket.example/event", link["href"]
    assert_equal "_blank", link["target"]
    assert_equal "noopener", link["rel"]
    assert_nil link["onclick"]
    assert_equal "/rails/active_storage/blobs/proxy/signed/photo.jpg", image["src"]
    assert_equal "Bühne", image["alt"]
    assert_nil fragment.at_css("a.event-detail-inline-link")
  end

  test "formatted venue description removes self links from rich text images" do
    image_path = "/rails/active_storage/blobs/proxy/signed/photo.jpg"
    fragment = Nokogiri::HTML.fragment(
      formatted_venue_description(
        %(<a href="#{image_path}"><figure class="attachment"><img src="#{image_path}" alt="Bühne"></figure></a>)
      )
    )

    assert_nil fragment.at_css("a")
    assert_equal image_path, fragment.at_css("figure.attachment img")["src"]
  end

  test "formatted venue description links plain text urls" do
    fragment = Nokogiri::HTML.fragment(
      formatted_venue_description("Infos unter https://venue.example/programm.")
    )

    link = fragment.at_css("a.event-detail-inline-link")

    assert_equal "Infos unter https://venue.example/programm.", fragment.text
    assert_equal "https://venue.example/programm", link["href"]
    assert_equal "_blank", link["target"]
    assert_equal "noopener", link["rel"]
  end

  test "formatted organizer notes renders headings and categorized lists" do
    notes = <<~TEXT
      Wichtige Sicherheitsregeln
      ❌ Handtaschen
      ❌ Rucksäcke

      Kontrollen beim Einlass
      - Alle Besucher werden abgetastet (Bodycheck)

      Was du mitbringen darfst
      ✅ Handy
      ✅ Medikamente
    TEXT

    fragment = Nokogiri::HTML.fragment(formatted_organizer_notes_with_link(notes))

    assert_equal [ "Wichtige Sicherheitsregeln", "Kontrollen beim Einlass", "Was du mitbringen darfst" ],
                 fragment.css(".event-detail-notes-heading").map(&:text)
    assert_equal [ "Handtaschen", "Rucksäcke" ],
                 fragment.css(".event-detail-notes-list-negative .event-detail-notes-list-text").map(&:text)
    assert_equal [ "Alle Besucher werden abgetastet (Bodycheck)" ],
                 fragment.css(".event-detail-notes-list-neutral .event-detail-notes-list-text").map(&:text)
    assert_equal [ "Handy", "Medikamente" ],
                 fragment.css(".event-detail-notes-list-positive .event-detail-notes-list-text").map(&:text)
  end

  test "formatted organizer notes hides preview entry controls section when normalizing headings" do
    notes = <<~TEXT
      Was du mitbringen darfst
      Handy, Schlüssel, Geldbeutel

      Kontrollen beim Einlass
      Alle Besucher werden abgetastet (Bodycheck)
      Es gibt strengere Sicherheitskontrollen als sonst
      Die Einhaltung dieser Regeln und Hinweise sowie ein rechtzeitiges Eintreffen helfen dabei, den Einlass so zügig wie möglich zu organisieren.
      Danke für euer Verständnis!

      Altersfreigabe
      kein Zutritt: unter 6 Jahren
    TEXT

    fragment = Nokogiri::HTML.fragment(formatted_organizer_notes_with_link(notes, normalize_headings: true))

    assert_equal [ "Was du mitbringen darfst", "Altersfreigabe" ],
                 fragment.css(".event-detail-notes-heading").map(&:text)
    assert_no_match "Bodycheck", fragment.text
    assert_includes fragment.text, "kein Zutritt: unter 6 Jahren"
  end

  test "formatted organizer notes replaces begleiformular shortcut with link" do
    notes = <<~TEXT
      Altersfreigabe:
      nur in Begleitung: bis 14 Jahren → Begleitformular PDF
    TEXT

    fragment = Nokogiri::HTML.fragment(formatted_organizer_notes_with_link(notes))

    assert_equal "Altersfreigabe", fragment.at_css(".event-detail-notes-heading")&.text
    assert_includes fragment.text, "nur in Begleitung: bis 14 Jahren"
    assert fragment.at_css("p br + a"), "expected the guardian form link to start on a new line"
    assert_equal "→ Begleitformular PDF", fragment.at_css("a")&.text&.squish
  end

  test "formatted organizer notes replaces du addressed begleiformular shortcut with link" do
    notes = "nur in Begleitung: bis 14 Jahren (Das Begleitformular findest du HIER)"

    fragment = Nokogiri::HTML.fragment(formatted_organizer_notes_with_link(notes))

    assert_includes fragment.text, "nur in Begleitung: bis 14 Jahren"
    assert_equal "→ Begleitformular PDF", fragment.at_css("a")&.text&.squish
  end
end
