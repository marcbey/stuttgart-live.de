require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

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

    assert_includes saved_lane_rules, "--lane-header-title-color: #15767d;"
    assert public_search_icon_rules.any? { |rule| rule.include?("width: 2.5rem;") }
    assert public_search_icon_rules.any? { |rule| rule.include?("height: 2.5rem;") }
    assert base_public_search_icon_rules.any? { |rule| rule.include?("width: 2.5rem;") }
    assert base_public_search_icon_rules.any? { |rule| rule.include?("height: 2.5rem;") }
  end

  test "public search controller keeps aria expanded off the native search input" do
    controller = Rails.root.join("app/javascript/controllers/public_search_controller.js").read

    refute_includes controller, 'inputTarget.setAttribute("aria-expanded"'
  end

  test "local font face stylesheet skips unavailable fonts" do
    original_method = method(:asset_available?)

    singleton_class.define_method(:asset_available?) do |logical_path|
      logical_path != "archivo-narrow-400.woff2"
    end

    stylesheet = local_font_face_stylesheet(frontend: false)

    refute_includes stylesheet, "archivo-narrow-400"
    assert_includes stylesheet, "archivo-narrow-700"
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

  test "formatted organizer notes replaces begleiformular shortcut with link" do
    notes = <<~TEXT
      Altersfreigabe:
      nur in Begleitung: bis 14 Jahren → Begleitformular PDF
    TEXT

    fragment = Nokogiri::HTML.fragment(formatted_organizer_notes_with_link(notes))

    assert_equal "Altersfreigabe", fragment.at_css(".event-detail-notes-heading")&.text
    assert_includes fragment.text, "nur in Begleitung: bis 14 Jahren"
    assert_equal "→ Begleitformular PDF", fragment.at_css("a")&.text&.squish
  end

  test "formatted organizer notes replaces du addressed begleiformular shortcut with link" do
    notes = "nur in Begleitung: bis 14 Jahren (Das Begleitformular findest du HIER)"

    fragment = Nokogiri::HTML.fragment(formatted_organizer_notes_with_link(notes))

    assert_includes fragment.text, "nur in Begleitung: bis 14 Jahren"
    assert_equal "→ Begleitformular PDF", fragment.at_css("a")&.text&.squish
  end
end
