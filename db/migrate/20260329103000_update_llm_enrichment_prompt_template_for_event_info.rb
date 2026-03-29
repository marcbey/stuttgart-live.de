class UpdateLlmEnrichmentPromptTemplateForEventInfo < ActiveRecord::Migration[8.1]
  class AppSettingMigration < ActiveRecord::Base
    self.table_name = "app_settings"
  end

  PREVIOUS_TEMPLATE = <<~TEXT.strip
    Ermittle zu den Events aus `Input` die fehlenden Felder

    - `genre`
    - `youtube_link`
    - `instagram_link`
    - `homepage_link`
    - `facebook_link`
    - `artist_description`
    - `event_description`
    - `venue_description`

    und gib das Ergebnis im selben JSON-Format zurück wie in `Output`.

    Wichtig:
    Die ermittelten Links und Informationen müssen für das Zielmodell „offiziell oder belastbar genug“ sein.
    Ziel ist ausdrücklich, möglichst viele korrekt zuordenbare Links für `youtube_link`, `instagram_link`, `homepage_link` und `facebook_link` zu finden. Sei deshalb bei der Recherche breit und beharrlich, aber nicht erfinderisch.

    Dabei gelten folgende Regeln:

    1. Bevorzuge für Links in dieser Reihenfolge:
      - `official`: offizielle Website oder offiziell wirkender verifizierbarer Künstler-/Projekt-/Venue-Account
      - `promoter`: offizielle Projekt-, Veranstalter- oder Tour-Seite eines bekannten Promoters / Managements / Veranstalters
      - `event_listing`: belastbare Event-Seite eines bekannten Ticketing- oder Venue-Portals
      - `social_post`: einzelner konkreter Social-Media-Post, wenn kein offizieller Account oder keine bessere Quelle verfügbar ist

    2. Suche für jeden der vier Link-Typen aktiv nach mehreren plausiblen Kandidaten und entscheide dich dann für den besten belastbaren Treffer. Prüfe insbesondere:
      - offizielle Artist-Website
      - offizielle Venue-Website
      - offizielle Tour- oder Projektseite
      - offizielle oder klar zuordenbare Social-Media-Profile
      - YouTube-Kanal oder offizieller Artist-/Venue-Channel
      - bekannte Veranstalter-, Management- oder Promoter-Seiten
      - bekannte Ticketing-, Venue- oder Festival-Listings

    3. Verwende einen Link nur dann, wenn er eindeutig dem Artist, Projekt, Event oder Venue zugeordnet werden kann. Bevorzuge dabei lieber einen schwächeren, aber noch belastbaren Treffer aus `promoter` oder `event_listing`, statt vorschnell `null` zu setzen.

    4. Wenn kein ausreichend belastbarer Link gefunden wird, setze das Feld auf `null`.

    5. Erfinde keine Links, Genres oder Beschreibungen.

    6. Wenn ein Event kein Musik-Act ist, sondern z. B. Theater, Schauspiel, Show oder Lesung, dann modelliere es fachlich korrekt und verwende passende Genres statt Musikgenres.

    7. Bei Projekt- oder Tour-Formaten wie z. B. Ensemble-, Tribute-, Jubiläums- oder Mehrkünstler-Events dürfen auch projektbezogene oder promoterbezogene Links verwendet werden, wenn keine klaren offiziellen Artist-Accounts existieren.

    8. Für Linkfelder gilt zusätzlich:
      - `homepage_link`: bevorzugt offizielle Artist-, Projekt- oder Venue-Website; ersatzweise offizielle Tour-/Promoter-Seite
      - `instagram_link`: bevorzugt offizielles Profil von Artist, Projekt oder Venue; wenn nicht vorhanden, ein klar zuordenbares Projekt-, Tour- oder Promoter-Profil
      - `facebook_link`: bevorzugt offizielle Facebook-Seite von Artist, Projekt, Venue oder Tour; ersatzweise belastbare Veranstalter-/Promoter-Seite
      - `youtube_link`: bevorzugt offizieller Kanal; ersatzweise klar zuordenbarer Topic-/Projekt-/Venue-Kanal oder ein belastbares einzelnes Video, wenn kein besserer Kanal auffindbar ist

    9. Prüfe jeden ausgewählten Link für `youtube_link`, `instagram_link`, `homepage_link` und `facebook_link` zusätzlich auf technische und inhaltliche Erreichbarkeit:
      - verwende einen Link nur, wenn die Zielseite erreichbar ist und kein HTTP-Fehler vorliegt, insbesondere kein `404` und kein sonstiger HTTP-Statuscode-Fehler
      - folge Redirects gedanklich bis zur tatsächlichen Zielseite; maßgeblich ist die letztlich geladene Seite, nicht nur die Ausgangs-URL
      - verwende keinen Link, wenn die Zielseite Hinweise auf Nichtverfügbarkeit enthält, insbesondere `Diese Seite ist leider nicht verfügbar` oder `Dieser Inhalt ist momentan nicht verfügbar`
      - wenn ein fachlich plausibler Kandidat technisch nicht erreichbar ist oder auf eine Fehler-/Nichtverfügbarkeitsseite führt, verwerfe ihn und prüfe den nächsten plausiblen Kandidaten
      - wenn kein belastbarer und zugleich erreichbarer Kandidat gefunden wird, setze das jeweilige Linkfeld auf `null`

    10. Beschreibungen sollen nüchtern, präzise und faktennah sein, aber deutlich ausführlicher als bisher:
      - `artist_description`: beschreibt Artist, Projekt oder Produktion
      - `event_description`: beschreibt das konkrete Event bzw. Tour-/Show-Format
      - `venue_description`: beschreibt den Veranstaltungsort
      - schreibe in vollständigen deutschen Sätzen
      - liefere nach Möglichkeit 3 bis 6 Sätze pro Feld
      - nenne musikalische, stilistische, historische oder programmatische Einordnung, wenn belastbar
      - nenne bei `event_description` nach Möglichkeit Inhalt, Format, Tour-Kontext, typische Erwartung des Publikums und Besonderheiten
      - nenne bei `venue_description` nach Möglichkeit Ort, Profil, Größe/Atmosphäre, Nutzungsschwerpunkt und Relevanz für das lokale Kulturleben
      - wenn nur wenig belastbare Information verfügbar ist, schreibe lieber einen vorsichtigen, aber immer noch substanziellen Text statt nur einen sehr kurzen Satz

    11. Ziehe auch den Eventtitel, die Venue und den wahrscheinlichen lokalen Kontext heran, um korrekte Projekt-, Tour- oder Venue-Treffer besser zu identifizieren.

    12. Wenn Artist-Name oder Event-Name mehrdeutig sind, gleiche immer mit Venue, Ort, Tourtitel oder Projektkontext ab, bevor du einen Link wählst.

    13. Falls du für einen Link keinen ausreichend belastbaren Treffer findest, gib für das Linkfeld `null` zurück.

    Antwort nur als JSON.

    Input:
    {{input_json}}
  TEXT

  UPDATED_TEMPLATE = <<~TEXT.strip
    Ermittle zu den Events aus `Input` die fehlenden Felder

    - `genre`
    - `youtube_link`
    - `instagram_link`
    - `homepage_link`
    - `facebook_link`
    - `artist_description`
    - `event_description`
    - `venue_description`

    und gib das Ergebnis im selben JSON-Format zurück wie in `Output`.

    Wichtig:
    Die ermittelten Links und Informationen müssen für das Zielmodell „offiziell oder belastbar genug“ sein.
    Ziel ist ausdrücklich, möglichst viele korrekt zuordenbare Links für `youtube_link`, `instagram_link`, `homepage_link` und `facebook_link` zu finden. Sei deshalb bei der Recherche breit und beharrlich, aber nicht erfinderisch.

    Dabei gelten folgende Regeln:

    1. Bevorzuge für Links in dieser Reihenfolge:
      - `official`: offizielle Website oder offiziell wirkender verifizierbarer Künstler-/Projekt-/Venue-Account
      - `promoter`: offizielle Projekt-, Veranstalter- oder Tour-Seite eines bekannten Promoters / Managements / Veranstalters
      - `event_listing`: belastbare Event-Seite eines bekannten Ticketing- oder Venue-Portals
      - `social_post`: einzelner konkreter Social-Media-Post, wenn kein offizieller Account oder keine bessere Quelle verfügbar ist

    2. Suche für jeden der vier Link-Typen aktiv nach mehreren plausiblen Kandidaten und entscheide dich dann für den besten belastbaren Treffer. Prüfe insbesondere:
      - offizielle Artist-Website
      - offizielle Venue-Website
      - offizielle Tour- oder Projektseite
      - offizielle oder klar zuordenbare Social-Media-Profile
      - YouTube-Kanal oder offizieller Artist-/Venue-Channel
      - bekannte Veranstalter-, Management- oder Promoter-Seiten
      - bekannte Ticketing-, Venue- oder Festival-Listings

    3. Verwende einen Link nur dann, wenn er eindeutig dem Artist, Projekt, Event oder Venue zugeordnet werden kann. Bevorzuge dabei lieber einen schwächeren, aber noch belastbaren Treffer aus `promoter` oder `event_listing`, statt vorschnell `null` zu setzen.

    4. Wenn kein ausreichend belastbarer Link gefunden wird, setze das Feld auf `null`.

    5. Erfinde keine Links, Genres oder Beschreibungen.

    6. Wenn ein Event kein Musik-Act ist, sondern z. B. Theater, Schauspiel, Show oder Lesung, dann modelliere es fachlich korrekt und verwende passende Genres statt Musikgenres.

    7. Bei Projekt- oder Tour-Formaten wie z. B. Ensemble-, Tribute-, Jubiläums- oder Mehrkünstler-Events dürfen auch projektbezogene oder promoterbezogene Links verwendet werden, wenn keine klaren offiziellen Artist-Accounts existieren.

    8. Für Linkfelder gilt zusätzlich:
      - `homepage_link`: bevorzugt offizielle Artist-, Projekt- oder Venue-Website; ersatzweise offizielle Tour-/Promoter-Seite
      - `instagram_link`: bevorzugt offizielles Profil von Artist, Projekt oder Venue; wenn nicht vorhanden, ein klar zuordenbares Projekt-, Tour- oder Promoter-Profil
      - `facebook_link`: bevorzugt offizielle Facebook-Seite von Artist, Projekt, Venue oder Tour; ersatzweise belastbare Veranstalter-/Promoter-Seite
      - `youtube_link`: bevorzugt offizieller Kanal; ersatzweise klar zuordenbarer Topic-/Projekt-/Venue-Kanal oder ein belastbares einzelnes Video, wenn kein besserer Kanal auffindbar ist

    9. Prüfe jeden ausgewählten Link für `youtube_link`, `instagram_link`, `homepage_link` und `facebook_link` zusätzlich auf technische und inhaltliche Erreichbarkeit:
      - verwende einen Link nur, wenn die Zielseite erreichbar ist und kein HTTP-Fehler vorliegt, insbesondere kein `404` und kein sonstiger HTTP-Statuscode-Fehler
      - folge Redirects gedanklich bis zur tatsächlichen Zielseite; maßgeblich ist die letztlich geladene Seite, nicht nur die Ausgangs-URL
      - verwende keinen Link, wenn die Zielseite Hinweise auf Nichtverfügbarkeit enthält, insbesondere `Diese Seite ist leider nicht verfügbar` oder `Dieser Inhalt ist momentan nicht verfügbar`
      - wenn ein fachlich plausibler Kandidat technisch nicht erreichbar ist oder auf eine Fehler-/Nichtverfügbarkeitsseite führt, verwerfe ihn und prüfe den nächsten plausiblen Kandidaten
      - wenn kein belastbarer und zugleich erreichbarer Kandidat gefunden wird, setze das jeweilige Linkfeld auf `null`

    10. Beschreibungen sollen nüchtern, präzise und faktennah sein, aber deutlich ausführlicher als bisher:
      - `artist_description`: beschreibt Artist, Projekt oder Produktion
      - `event_description`: beschreibt das konkrete Event bzw. Tour-/Show-Format
      - `venue_description`: beschreibt den Veranstaltungsort
      - schreibe in vollständigen deutschen Sätzen
      - liefere nach Möglichkeit 3 bis 6 Sätze pro Feld
      - nenne musikalische, stilistische, historische oder programmatische Einordnung, wenn belastbar
      - nenne bei `event_description` nach Möglichkeit Inhalt, Format, Tour-Kontext, typische Erwartung des Publikums und Besonderheiten
      - nenne bei `venue_description` nach Möglichkeit Ort, Profil, Größe/Atmosphäre, Nutzungsschwerpunkt und Relevanz für das lokale Kulturleben
      - wenn nur wenig belastbare Information verfügbar ist, schreibe lieber einen vorsichtigen, aber immer noch substanziellen Text statt nur einen sehr kurzen Satz

    11. Nutze zusätzlich `event_info` aus dem Input als Kontextquelle für Disambiguierung, fachliche Einordnung und belastbarere Beschreibungen. Behandle `event_info` als hilfreichen Hinweistext zum konkreten Event, aber nicht als automatisch verifizierte Tatsache.

    12. Ziehe auch den Eventtitel, die Venue und den wahrscheinlichen lokalen Kontext heran, um korrekte Projekt-, Tour- oder Venue-Treffer besser zu identifizieren.

    13. Wenn Artist-Name oder Event-Name mehrdeutig sind, gleiche immer mit Venue, Ort, Tourtitel, Projektkontext und `event_info` ab, bevor du einen Link wählst.

    14. Falls du für einen Link keinen ausreichend belastbaren Treffer findest, gib für das Linkfeld `null` zurück.

    Antwort nur als JSON.

    Input:
    {{input_json}}
  TEXT

  def up
    setting = AppSettingMigration.find_by(key: "llm_enrichment_prompt_template")
    return unless setting

    normalized_value = setting.value.to_s.strip
    return unless normalized_value == PREVIOUS_TEMPLATE

    setting.update!(value: UPDATED_TEMPLATE)
  end

  def down
    setting = AppSettingMigration.find_by(key: "llm_enrichment_prompt_template")
    return unless setting

    normalized_value = setting.value.to_s.strip
    return unless normalized_value == UPDATED_TEMPLATE

    setting.update!(value: PREVIOUS_TEMPLATE)
  end
end
