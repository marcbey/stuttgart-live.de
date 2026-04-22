class UpdateLlmEnrichmentPromptTemplateForSearchContext < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  PREVIOUS_TEMPLATE = <<~TEXT.strip
    Ermittle zu den Events aus `Input` die fehlenden Felder

    - `genre`
    - `event_description`
    - `venue_description`
    - `venue_external_url`
    - `venue_address`

    und gib das Ergebnis im selben JSON-Format zurück wie in `Output`.

    Wichtig:
    Die ermittelten Informationen müssen belastbar sein. `venue_external_url` und `venue_address` sollen sich klar dem Veranstaltungsort zuordnen lassen.

    Dabei gelten folgende Regeln:

    1. Erfinde keine Genres, Beschreibungen oder Venue-Metadaten.

    2. `genre` meint immer eine fachliche stilistische oder spartenbezogene Einordnung, nicht den bloßen Eventtyp oder einen Containerbegriff:
      - verwende nur belastbare fachliche Genres oder Sparten
      - verboten sind generische Meta-Begriffe wie `show`, `concert`, `event`, `live`, `veranstaltung`, `konzert` oder sinngleiche Containerlabels
      - wenn ein Event kein Musik-Act ist, verwende stattdessen passende fachliche Sparten wie z. B. `Theater`, `Comedy`, `Kabarett`, `Lesung`, `Tanz`, `Musical` oder `Oper`, sofern belastbar
      - wenn kein belastbares fachliches Genre ermittelbar ist, gib lieber ein leeres Genre-Array zurück, statt ein generisches Meta-Genre zu erfinden oder zu raten

    3. Für Venue-Metadaten gilt zusätzlich:
      - `venue_external_url`: bevorzugt die offizielle Website des Veranstaltungsorts; ersatzweise eine klar zuordenbare offizielle Profil- oder Hausseite des Venues
      - `venue_address`: möglichst vollständige öffentlich belastbare Adresse des Veranstaltungsorts

    4. Beschreibungen sollen nüchtern, präzise und faktennah sein, aber deutlich ausführlicher als bisher:
      - `event_description`: beschreibt Artist, Projekt oder Produktion sowie das konkrete Event bzw. Tour-/Show-Format in einem zusammenhängenden Text ohne Wiederholungen
      - `venue_description`: beschreibt den Veranstaltungsort
      - schreibe in vollständigen deutschen Sätzen
      - liefere nach Möglichkeit 3 bis 6 Sätze pro Feld
      - nenne musikalische, stilistische, historische oder programmatische Einordnung, wenn belastbar
      - nenne bei `event_description` nach Möglichkeit Artist-/Projektprofil, Inhalt, Format, Tour-Kontext, typische Erwartung des Publikums und Besonderheiten
      - fasse überlappende Informationen zu Artist und Event zusammen, statt dieselben Fakten doppelt zu nennen
      - nenne bei `venue_description` nach Möglichkeit Ort, Profil, Größe/Atmosphäre, Nutzungsschwerpunkt und Relevanz für das lokale Kulturleben
      - wenn nur wenig belastbare Information verfügbar ist, schreibe lieber einen vorsichtigen, aber immer noch substanziellen Text statt nur einen sehr kurzen Satz

    5. Nutze zusätzlich `event_info` aus dem Input als Kontextquelle für Disambiguierung, fachliche Einordnung und belastbarere Beschreibungen. Behandle `event_info` als hilfreichen Hinweistext zum konkreten Event, aber nicht als automatisch verifizierte Tatsache.

    6. Ziehe auch den Eventtitel, die Venue und den wahrscheinlichen lokalen Kontext heran, um korrekte Projekt-, Tour- oder Venue-Treffer besser zu identifizieren.

    7. Wenn Artist-Name oder Event-Name mehrdeutig sind, gleiche immer mit Venue, Ort, Tourtitel, Projektkontext und `event_info` ab, bevor du ein Genre, eine Beschreibung oder Venue-Metadaten festlegst.

    8. Falls du für `venue_external_url` oder `venue_address` keinen ausreichend belastbaren Treffer findest, gib für das jeweilige Feld `null` zurück.

    Antwort nur als JSON.

    Output:
    {
      "events": [
        {
          "event_id": 123,
          "genre": [ "Indie Pop" ],
          "venue": "Beispiel Venue",
          "event_description": "Beispieltext.",
          "venue_description": "Beispieltext.",
          "venue_external_url": "https://venue.example",
          "venue_address": "Beispielstraße 1, 70173 Stuttgart"
        }
      ]
    }

    Input:
    {{input_json}}
  TEXT

  def up
    setting = AppSettingMigration.find_by(key: "llm_enrichment_prompt_template")
    return unless setting
    return unless setting.value.to_s.strip == PREVIOUS_TEMPLATE

    setting.update!(value: AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE)
  end

  def down
    setting = AppSettingMigration.find_by(key: "llm_enrichment_prompt_template")
    return unless setting
    return unless setting.value.to_s.strip == AppSetting::LLM_ENRICHMENT_PROMPT_TEMPLATE

    setting.update!(value: PREVIOUS_TEMPLATE)
  end
end
