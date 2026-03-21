# TODOs

## Infra
- DB Backup & File Backup Strategie
- Rollbacks inkl. migration rollbacks ausprobieren
- OWASP checks initial & evtl. als bin/ci ?
- Plan für Data Rentention
- Logfile Rotation
- Ruby 4 upgrade_
- Monitoring/Alerting : uptimekuma.org

## Importer

## Events Backend
- Promoter ID mapping (SKS, Music Circus, ...)
- Events gruppieren

## Frontend
- Feld Banderole unklar:
    - Ausverkauft, Neue Tickets vorhanden, Zusatztermin, Neu im Vorverkauf, 
    - Exlusive Deutschlandshow, Abgesagt, Jetzt Tickets sichern
    - Neuer Termin - Karten bleiben gültig, Verlegt auf ..., 
- Newsletter/Mailchimp
- Google Analytics


# Konzepte

## Events gruppieren

Es gibt Events die logisch zusammen gehören (Event-Reihen).
Event-Reihen können mehrfach täglich (unterschiedliche Uhrzeiten am selben Tag) und/oder mehrfach wöchentlich (unterschiedliches Datum) stattfinden.
Event-Reihen können auch durch zukünftige Imports nachträglich erweitert werden.
Ein Beispiel für eine solche Event-Reihe: "Viva la Vida: A Tribute to Frida Kahlo".

Backend UI:
Event-Reihen sollen im Backend UI logisch zusammen gefasst werden können.
Eine Zusammenfassung zu einer Event-Reihe muss reversible sein.
Ein Event von einer Event-Reihe muss textuell & visuell erkennbar sein: zusammenhängende Events sollen als Event-Reihe identfizierbar sein.
Im aside backend-list-column über die Filter in filter-form werden zusammengehörige Events ermittelt und über die Checkboxen event-checkbox in der Event-Liste events_list ausgewählt.
Der dropdown bulk_action soll mit eine Option "Als Event-Reihe zusammenfassen" hinzugefügt werden.
Diese zusätzliche Aktion/Option "Als Event-Reihe zusammenfassen" legt die Event-Reihe mit den ausgewählten Events an.

Frontend:
Im Frontend zeigen die Event-Reihen an folgenden Stellen Auswirkung:
In den Teaser Slider Lanes: Dort soll ...
