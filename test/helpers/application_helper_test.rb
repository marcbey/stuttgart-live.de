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
end
