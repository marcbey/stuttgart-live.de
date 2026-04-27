class UpdateLlmEnrichmentPromptTemplateForDirectVenueUrl < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  PREVIOUS_TEMPLATE = <<~TEXT.strip
    Ermittle für genau ein Event aus `Input` die fehlenden Felder

    - `genre`
    - `homepage_link`
    - `instagram_link`
    - `facebook_link`
    - `youtube_link`
    - `event_description`
    - `venue_description`
    - `venue_external_url`
    - `venue_address`

    und gib das Ergebnis im selben JSON-Format zurück wie in `Output`.

    Wichtig:
    Die ermittelten Informationen müssen belastbar sein. `venue_external_url` und `venue_address` sollen sich klar dem Veranstaltungsort zuordnen lassen.
    Für `homepage_link`, `instagram_link`, `facebook_link`, `youtube_link` und `venue_external_url` darfst du ausschließlich Links aus `search_results.fields.<feld>.candidates` auswählen. Freie Link-Erfindung ist verboten.

    Dabei gelten folgende Regeln:

    1. Erfinde keine Genres, Beschreibungen, Venue-Metadaten oder Links.

    2. Für die fünf Linkfelder gilt zwingend:
      - `homepage_link`, `instagram_link`, `facebook_link`, `youtube_link` und `venue_external_url` dürfen nur einen Link aus den mitgelieferten Kandidatenlisten enthalten
      - wenn keiner der Kandidaten passt, gib für das jeweilige Feld `null` zurück
      - bewerte die Kandidaten anhand von `title`, `displayed_link`, `snippet`, `source`, `about_source_description`, `languages` und `regions`
      - `venue_external_url` bezieht sich auf den Veranstaltungsort, nicht auf den Artist
      - `search_results` enthält pro Feld höchstens 10 Treffer; wähle nur dann einen Link, wenn die Zuordnung zum Event klar belastbar ist

    3. `genre` meint immer eine fachliche stilistische oder spartenbezogene Einordnung, nicht den bloßen Eventtyp oder einen Containerbegriff:
      - verwende nur belastbare fachliche Genres oder Sparten
      - verboten sind generische Meta-Begriffe wie `show`, `concert`, `event`, `live`, `veranstaltung`, `konzert` oder sinngleiche Containerlabels
      - wenn ein Event kein Musik-Act ist, verwende stattdessen passende fachliche Sparten wie z. B. `Theater`, `Comedy`, `Kabarett`, `Lesung`, `Tanz`, `Musical` oder `Oper`, sofern belastbar
      - wenn kein belastbares fachliches Genre ermittelbar ist, gib lieber ein leeres Genre-Array zurück, statt ein generisches Meta-Genre zu erfinden oder zu raten

    4. Für Venue-Metadaten gilt zusätzlich:
      - `venue_external_url`: bevorzugt die offizielle Website des Veranstaltungsorts; ersatzweise eine klar zuordenbare offizielle Profil- oder Hausseite des Venues
      - `venue_address`: möglichst vollständige öffentlich belastbare Adresse des Veranstaltungsorts

    5. Für die Social-Link-Felder gilt zusätzlich:
      - `homepage_link`: bevorzugt offizielle Artist-, Projekt- oder Event-Website
      - `instagram_link`: bevorzugt offizielles Profil von Artist oder Projekt
      - `facebook_link`: bevorzugt offizielle Facebook-Seite von Artist, Projekt oder Tour
      - `youtube_link`: bevorzugt offizieller Kanal; nur wenn kein besserer Kandidat vorhanden ist, ist ein klar zuordenbares einzelnes Video zulässig

    6. Beschreibungen sollen nüchtern, präzise und faktennah sein, aber deutlich ausführlicher als bisher:
      - `event_description`: beschreibt Artist, Projekt oder Produktion sowie das konkrete Event bzw. Tour-/Show-Format in einem zusammenhängenden Text ohne Wiederholungen
      - `venue_description`: beschreibt den Veranstaltungsort
      - schreibe in vollständigen deutschen Sätzen
      - liefere nach Möglichkeit 3 bis 6 Sätze pro Feld
      - nenne musikalische, stilistische, historische oder programmatische Einordnung, wenn belastbar
      - nenne bei `event_description` nach Möglichkeit Artist-/Projektprofil, Inhalt, Format, Tour-Kontext, typische Erwartung des Publikums und Besonderheiten
      - fasse überlappende Informationen zu Artist und Event zusammen, statt dieselben Fakten doppelt zu nennen
      - nenne bei `venue_description` nach Möglichkeit Ort, Profil, Größe/Atmosphäre, Nutzungsschwerpunkt und Relevanz für das lokale Kulturleben
      - wenn nur wenig belastbare Information verfügbar ist, schreibe lieber einen vorsichtigen, aber immer noch substanziellen Text statt nur einen sehr kurzen Satz

    7. Nutze zusätzlich `event_info` aus dem Input als Kontextquelle für Disambiguierung, fachliche Einordnung und belastbarere Beschreibungen. Behandle `event_info` als hilfreichen Hinweistext zum konkreten Event, aber nicht als automatisch verifizierte Tatsache.

    8. Ziehe auch den Eventtitel, die Venue und den wahrscheinlichen lokalen Kontext heran, um korrekte Projekt-, Tour- oder Venue-Treffer besser zu identifizieren.

    9. Wenn Artist-Name oder Event-Name mehrdeutig sind, gleiche immer mit Venue, Ort, Tourtitel, Projektkontext und `event_info` ab, bevor du ein Genre, eine Beschreibung, einen Venue-Link oder einen Social-Link festlegst.

    10. Falls du für `venue_external_url` oder `venue_address` keinen ausreichend belastbaren Treffer findest, gib für das jeweilige Feld `null` zurück.

    Antwort nur als JSON.

    Output:
    {
      "event_id": 123,
      "genre": [ "Indie Pop" ],
      "homepage_link": "https://artist.example",
      "instagram_link": "https://www.instagram.com/artist/",
      "facebook_link": "https://www.facebook.com/artist",
      "youtube_link": "https://www.youtube.com/@artist",
      "venue": "Beispiel Venue",
      "event_description": "Beispieltext.",
      "venue_description": "Beispieltext.",
      "venue_external_url": "https://venue.example",
      "venue_address": "Beispielstraße 1, 70173 Stuttgart"
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
