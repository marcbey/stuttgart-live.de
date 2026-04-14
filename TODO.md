# TODOs

## Infra
- DB Backup & File Backup Strategie
- Rollbacks inkl. migration rollbacks ausprobieren
- OWASP checks
- Sentry CLI/MCP einrichten

## Importer

## Events Backend
- POSTPONE: Promoter ID mapping (SKS, Music Circus, ...)

## Frontend
- Newsletter/Mailchimp
- Google Analytics
- getrennte CSS files für Frontend & Backend

# DONE:
- Venue: soll eigenes Domain Model mit Beschreibung, Logo, Link, Adresse, Google Maps Link, überschreibt die LLM Venue
- LLM Beschreibung + über den act + über die venue zusammen legen
- Genre Gruppierung tunen
- Suche: robuster machen, zB Leerzeichen
- Suche: default Suchergebnis soll auch Promotion Events zeigen + SKS Events, max ~5 Events
- Promotion Banner: Dort das Event Image mit crop anzeigen
- Main Nav: Tiktok Icon + Link
- Main Nav: Insta Link falsch
- Prompt verbessern: Social Links überprüfen
- Data Rentention: Events mit Status draft, unpublished & rejected entfernen wenn älter als ~1 Monat
- Importer: Event Updates die später erst die Images bringen, ändert das beim update dann den Status von draft => published ?
- Importer: Merge Import auch automatisch jede Nacht, triggert dann das LLM-Enrichment
- Event Backend: Import-Änderungen je Merge nach Datum auswählen lassen
- Events: wenn ausverkauft, kein Ticket Link anzeigen? Was ist das Signal für ausverkauft?
- Events: wenn in der Vergangenheit, kein Ticket Link - deutlich kennzeichnen
- Event Editor: Promoter-ID fix - read-only
- New Event: Promoter-ID fix - read-only
- Event: Event Promotion Banner ganz nach oben
- New Event: Veröffentlichungs Datum einführen und auch erst dann veröffentlichen
- Noch nicht veröffentlichte Events, sollen automatisch "unpublished" sein, ein Job "published" sie wenn Veröffentlichungs Datum >= now()
- Bug: Veröffentlichunsdatum wird nicht gespeichert
- SKS & Highlight Events nur in der Highlight Lane nach vorne schieben, nicht in den anderen Lanes
- Ticket ausverkauft Checkbox im Event-Editor soll nur Text sein, plus ein Text-Input für SKS Events bei ausverkauften Events + darstellung auf der Event Detail
- Event: favourites merken in local storage, gemerkte Events irgendwie, irgendwo anzeigen
- CMS: Alle statische Seiten sollen pflegbar sein (CMS)
- Suche: erweitern, zielgerichet mit Datum (heute, morgen, Wochenende), Genre
- Suche: Suchergebnis mit besserem Aufbau, Design, etc...


# TODO:
- Genre: Obergruppen fix definieren und im LLM-Enrichment mit geben, macht einen LLM-entrichmenr re-run notwendig
- Listenansicht: einschränken: desktop 6 rows, mobile 10 events
- Listenansicht: Filter nach Genre & Venue ? Oder irgendwie über die globale Suche lösen
- Suche: Auf Mobile optimieren
- Bug: SKS Sonderlocke & Event Ausverkauft
 
# POSTPONE:
- Events: teure Seminare nach Preis filter? Was für Lösungen gibt es noch?

# Social Media Export

## Insta: 
https://www.instagram.com/sl_test_26/
Name: sl_test_26
eMail: chantalerler@russ-live.de
Password: af6mCSk7

## Facebook:
https://www.facebook.com/profile.php?id=61575281852595
eMail: stuttgart.live.concert@gmail.com
Password: LIVE0711MRuss!2025

 
 

