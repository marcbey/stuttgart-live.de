class ExtendSksSecurityNotes < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  OLD_NOTES = <<~TEXT.strip
    Wichtige Sicherheitsregeln
    ❌ Handtaschen
    ❌ Rucksäcke
    ❌ Helme
    ❌ Behälter aller Art

    Kontrollen beim Einlass
    - Alle Besucher werden abgetastet (Bodycheck)
    - Es gibt strengere Sicherheitskontrollen als sonst

    Was du mitbringen darfst
    Nur wirklich notwendige Dinge, zum Beispiel:
    ✅ Handy
    ✅ Schlüssel
    ✅ Geldbeutel
    ✅ Medikamente
    ✅ Kleine Kosmetikartikel
    - Aber nur in kleinen Taschen (maximal Größe DIN A4)
  TEXT

  NEW_NOTES = <<~TEXT.strip
    Wichtige Sicherheitsregeln
    ❌ Handtaschen
    ❌ Rucksäcke
    ❌ Helme
    ❌ Behälter aller Art

    Kontrollen beim Einlass
    - Alle Besucher werden abgetastet (Bodycheck)
    - Es gibt strengere Sicherheitskontrollen als sonst

    Was du mitbringen darfst
    Nur wirklich notwendige Dinge, zum Beispiel:
    ✅ Handy
    ✅ Schlüssel
    ✅ Geldbeutel
    ✅ Medikamente
    ✅ Kleine Kosmetikartikel
    - Aber nur in kleinen Taschen (maximal Größe DIN A4)

    Die Einhaltung dieser Regeln und Hinweise sowie ein rechtzeitiges Eintreffen helfen dabei, den Einlass so zügig wie möglich zu organisieren.

    Wir danken für Ihr Verständnis!

    Altersfreigabe:
    kein Zutritt: unter 6 Jahren
    nur in Begleitung: bis 14 Jahren → Begleitformular PDF
    frei ab 14 Jahren

    Telefonischer Ticketkauf:

    Bei dieser Veranstaltung gibt es auch die Möglichkeit des telefonischen Ticketkaufes. Sie erreichen unsere Tickethotline in der Regel von Montag bis Freitag zwischen 10 und 18 Uhr unter Telefon 0711-550 660 77
  TEXT

  def up
    change_column_default :events, :organizer_notes, from: OLD_NOTES, to: NEW_NOTES

    setting = AppSettingMigration.find_or_initialize_by(key: "sks_organizer_notes")
    setting.update!(value: NEW_NOTES)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "security notes were extended with age rating and ticket hotline details"
  end
end
