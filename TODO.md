# TODOs

## Infra
- DB Backup & File Backup Strategie
- Rollbacks inkl. migration rollbacks ausprobieren
- OWASP checks initial & evtl. als bin/ci ?
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

# Bugs
- Listenansicht: einschränken: desktop 6 rows, mobile 10 events
- Listenansicht: Filter nach Genre & Venue ? Oder irgendwie über die globale Suche lösen
- Venue: soll eigenes Domain Model mit Beschreibung, Logo, Link, Adresse, Google Maps,  überschreibt die LLM Venue
- Suchergebnis Seite: mit Kachel / Listenansicht, generell anderes Layout

- DONE: Suche: robuster machen, zB Leerzeichen
- DONE: Suche: default Suchergebnis soll auch Promotion Events zeigen + SKS Events, max ~5 Events
- DONE: Promotion Banner: Dort das Event Image mit crop anzeigen
- DONE: Main Nav: Tiktok Icon + Link
- DONE: Main Nav: Insta Link falsch
- DONE: Prompt verbessern: Social Links überprüfen
- DONE: Data Rentention: Events mit Status draft, unpublished & rejected entfernen wenn älter als ~1 Monat
- DONE: Importer: Event Updates die später erst die Images bringen, ändert das beim update dann den Status von draft => published ?
- DONE: Importer: Merge Import auch automatisch jede Nacht, triggert dann das LLM-Enrichment
- DONE: Event Backend: Import-Änderungen je Merge nach Datum auswählen lassen
- Events: wenn ausverkauft, kein Ticket Link anzeigen? Was ist das Signal für ausverkauft?
- DONE: Events: wenn in der Vergangenheit, kein Ticket Link - deutlich kennzeichnen
- DONE: Event Editor: Promoter-ID fix - read-only
- DONE: New Event: Promoter-ID fix - read-only
- DONE: Event: Event Promotion Banner ganz nach oben
- DONE: New Event: Veröffentlichungs Datum einführen und auch erst dann veröffentlichen
- 
- Events: teure Seminare nach Preis filter? Was für Lösungen gibt es noch?
- Event: merken in local storage, gemerkte Events irgendwie, irgendwo anzeigen

# Konzepte
