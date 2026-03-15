class SeedSksOrganizerNotesSetting < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  SKS_ORGANIZER_NOTES = <<~TEXT.strip
    Wir bitten um Beachtung verstärkter Sicherheitsmaßnahmen
    Verbot von Handtaschen, Rucksäcken und Helmen
    Zusätzliche verschärfte Kontrollen und Bodychecks
    Sämtliche Besucher werden Bodychecks unterzogen. Taschen, Rucksäcke und Handtaschen sowie Helme und Behältnisse aller Art sind verboten.
    Die Zuschauer werden ausdrücklich gebeten, auf deren Mitbringen zu verzichten, und sich ausschließlich auf wirklich notwendige Utensilien wie Handys, Schlüsselbund und Portemonnaies sowie Medikamente oder Kosmetika in Gürteltaschen oder Kosmetiktäschchen bis zu einer maximalen Größe von Din A4 zu beschränken.
    Die Einhaltung dieser Regeln und Hinweise sowie ein rechtzeitiges Eintreffen helfen dabei, den Einlass so zügig wie möglich zu organisieren.

    Wir danken für Ihr Verständnis!

    Altersfreigabe:
    kein Zutritt: unter 6 Jahren
    nur in Begleitung: bis 14 Jahren (Das Begleitformular findest Du HIER)
    frei ab 14 Jahren

    Telefonischer Ticketkauf:

    Bei dieser Veranstaltung gibt es auch die Möglichkeit des telefonischen Ticketkaufes. Sie erreichen unsere Tickethotline in der Regel von Montag bis Freitag zwischen 10 und 18 Uhr unter Telefon 0711-550 660 77
  TEXT

  def up
    AppSettingMigration.find_or_create_by!(key: "sks_organizer_notes") do |setting|
      setting.value = SKS_ORGANIZER_NOTES
    end
  end

  def down
    AppSettingMigration.where(key: "sks_organizer_notes", value: SKS_ORGANIZER_NOTES).delete_all
  end
end
