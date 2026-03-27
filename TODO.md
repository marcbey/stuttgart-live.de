# TODOs

## Infra
- DB Backup & File Backup Strategie
- Rollbacks inkl. migration rollbacks ausprobieren
- OWASP checks initial & evtl. als bin/ci ?
- Plan für Data Rentention
- Monitoring/Alerting : uptimekuma.org

## Importer
- kann man erkennen ob die Tickets zu einem Event Ausverkauft sind oder evtl. noch andere Statues

## Events Backend
- Promoter ID mapping (SKS, Music Circus, ...)

## Frontend
- Feld Banderole unklar:
    - Ausverkauft, Neue Tickets vorhanden, Zusatztermin, Neu im Vorverkauf, 
    - Exlusive Deutschlandshow, Abgesagt, Jetzt Tickets sichern
    - Neuer Termin - Karten bleiben gültig, Verlegt auf ..., 
- Newsletter/Mailchimp
- Google Analytics


# Konzepte

## Events gruppieren
Können Event Gruppierungen in den Importer Roh-Daten erkannt werden?
Ein Beispiel für eine solche Event-Reihe: "Viva la Vida: A Tribute to Frida Kahlo".


Es gibt Events die logisch zusammen gehören (Event-Reihen).
Event-Reihen können mehrfach täglich (unterschiedliche Uhrzeiten am selben Tag) und/oder mehrfach wöchentlich (unterschiedliches Datum) stattfinden.
Event-Reihen können auch durch zukünftige Imports oder manuell erstelle Events nachträglich erweitert werden.
Ein Beispiel für eine solche Event-Reihe: "Viva la Vida: A Tribute to Frida Kahlo".

Backend UI:
Event-Reihen sollen im Backend UI logisch zusammen gefasst werden können.
Eine Zusammenfassung zu einer Event-Reihe muss reversible sein.
Ein Event von einer Event-Reihe muss textuell & visuell erkennbar sein: zusammenhängende Events sollen als Event-Reihe identfizierbar sein.
Über die Filter in filter-form im aside backend-list-column werden zusammengehörige Events ermittelt und über die Checkboxen event-checkbox der Event-Liste events_list ausgewählt.
Der dropdown bulk_action soll mit eine Option "Als Event-Reihe zusammenfassen" hinzugefügt werden.
Diese zusätzliche dropdown Option "Als Event-Reihe zusammenfassen" legt die Event-Reihe mit den ausgewählten Events an und führt die Aktion aus die Event-Reihe persistiert.

Backend:
- ein Event von einer Event-Reihe muss textuell & visuell erkennbar sein: zusammenhängende Events sollen als Event-Reihe identfizierbar sein.

Im Frontend haben Event-Reihen an folgenden Stellen eine Auswirkung:

Homepage:
- In allen Event Teaser Lanes wird nur der aktuellste Event dieser Event-Reihe gezeigt.
- Ein Event einer Event-Reihe bekommt eine spezielle Banderole mit dem Hinweis "Event-Reihe"

Event Detail Page:
- überhalb der Event Teaser Lane "Mehr aus diesem Genre" gibt es weitere Lane mit allen zukünftigen Events dieser Event-Reihe mit dem Event Title als Überschrift.

# Bugs
- DONE: Suche: robuster machen, zB Leerzeichen
- DONE: Suche: default Suchergebnis soll auch Promotion Events zeigen + SKS Events, max ~5 Events
- DONE: Promotion Banner: Dort das Event Image mit crop anzeigen
- DONE: Main Nav: Tiktok Icon + Link
- DONE: Main Nav: Insta Link falsch
- Listenansicht: einschränken: desktop 6 rows, mobile 10 events
- Listenansicht: Filter nach Genre & Venue ? Oder irgendwie über die globale Suche lösen
- Suchergebnis Seite: mit Kachel / Listenansicht, generell anderes Layout
- Prompt verbessern: Social Links überprüfen
- Venue: soll eigenes Domain Model mit Beschreibung, Logo, Link, Adresse, Google Maps,  überschreibt die LLM Venue
- Data Rentention: Events mit Status draft, unpublished & rejected entfernen wenn älter als ~1 Monat
- DONE: Importer: Event Updates die später erst die Images bringen, ändert das beim update dann den Status von draft => published ?
- Importer: Merge Import auch automatisch jede Nacht, triggert dann das LLM-Enrichment
- Event Backend: Import-Änderungen je Merge nach Datum auswählen lassen
- Events: teure Seminare nach Preis filter? Was für Lösungen gibt es noch?
- Events: wenn ausverkauft, kein Ticket Link anzeigen? Was ist das Signal für ausverkauft?
- Events: wenn in der Vergangenheit, kein Ticket Link - deutlich kennzeichnen
- Event Editor: Promoter-ID fix - read-only
- New Event: Veröffentlichungs Datum einführen und auch erst dann veröffentlichen
- New Event: Promoter-ID fix - read-only
- Event: merken in local storage, gemerkte Events irgendwie, irgendwo anzeigen
- Event: Event Promotion Banner ganz nach oben
