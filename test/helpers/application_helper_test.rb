require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

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
