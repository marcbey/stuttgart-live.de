# Eventim Ticket Offer Repair

## Ziel

Eventim-Ticketlinks sollen bei Eventim-ID-Wechseln auf die aktuell gültige Eventim-Eventseite zeigen. Der Fix soll die gemeldeten Reihen `Disneys DIE EISKÖNIGIN`, `WE WILL ROCK YOU` und `& Julia - Das Pop-Musical in Stuttgart` automatisch abdecken, ohne eine fragile Whitelist für genau diese Reihen einzubauen.

Der Fix besteht aus zwei Teilen:

- dauerhafte Merge-Logik, damit neue Eventim-ID-Wechsel künftig nicht wieder alte Links gewinnen lassen
- kontrollierter Backfill für bereits gespeicherte `event_offers`, mit Dry-Run und Serien-Zusammenfassung vor der Änderung

## Problem

Eventim kann für dieselbe Vorstellung eine neue `eventid` liefern. In den Raw-Imports liegen dann alte und neue Eventim-Records nebeneinander, weil der aktuelle Import-Schlüssel `source_identifier` aus `eventid:date` besteht.

Beim Merge erzeugt `Merging::SyncFromImports::EventUpserter` aktuell für jede Eventim-`eventid` ein eigenes `EventOffer`. Die öffentliche Auswahl nimmt bei gleicher Quelle und gleicher Priorität die ältere Datenbankzeile zuerst. Dadurch kann die alte, inzwischen ungültige Eventim-ID öffentlich angezeigt werden.

Live geprüft:

- Eiskönigin `2026-07-02`: alte ID `21189864` ist ungültig, neue ID `21554019` führt zur korrekten Eventim-Seite.
- We Will Rock You `2026-07-02`: alte ID `21198972` ist ungültig, neue ID `21564930` führt zur korrekten Eventim-Seite.
- Julia hat denselben strukturellen Befund in größerem Umfang: mehrere zukünftige Events mit altem und neuem Eventim-Angebot in derselben Reihe.

Die Beispiele vom `2026-07-01` hatten keinen Ticketlink, weil die Events am `2026-07-02` bereits vergangen waren. Es gab dort keinen Hinweis auf eine manuelle Deaktivierung.

## Wichtige Einschränkung

Nicht jedes doppelte Eventim-Angebot ist ein Eventim-ID-Wechsel. In den Produktionsdaten gibt es auch:

- Zusatzprodukte wie VIP, Meet & Greet, Packages oder Upgrades
- gemischte Eventim-Serien-IDs am selben Startzeitpunkt, die eher ein Merge-/Matching-Thema sind

Deshalb ist `höchste Eventim-ID gewinnt` kein sicherer Fix.

## Geplantes Design

### 1. ImportRecord bekommt Raw-Import-Provenienz

Dateien:

- `app/services/merging/sync_from_imports.rb`
- `app/services/merging/sync_from_imports/record_builders/base.rb`
- betroffene Tests, die `Merging::SyncFromImports::ImportRecord.new` direkt bauen

Ergänze `ImportRecord` um:

- `raw_import_id`
- `raw_import_created_at`

Diese Werte werden nur für deterministische Auswahl und Backfill benötigt. Es ist keine Datenbankmigration nötig.

### 2. Eventim-Angebote klassifizieren

Neue Datei:

- `app/services/importing/eventim/ticket_offer_classifier.rb`

Aufgabe:

- erkennt starke Zusatzprodukt-Signale in Eventim-Payloads, etwa `vip`, `meet & greet`, `package`, `upgrade`, `early entry`
- liefert `main` oder `auxiliary`
- extrahiert eine konservative Serien-/Vorstellungsidentität für Eventim:
  - `esid`
  - `start_at`
  - normalisierte Venue

Regel:

- Nur starke Zusatzprodukt-Treffer werden als `auxiliary` behandelt.
- Records ohne `esid` werden nicht über Eventim-ID-Grenzen hinweg zusammengelegt.
- Records mit unterschiedlicher `esid` werden nicht zusammengelegt.

### 3. Eventim-Offer-Consolidator in den Merge einhängen

Neue Datei:

- `app/services/merging/sync_from_imports/eventim_offer_consolidator.rb`

Geänderte Datei:

- `app/services/merging/sync_from_imports/event_upserter.rb`

Logik:

- Nicht-Eventim-Angebote bleiben unverändert.
- Eventim-Main-Angebote mit derselben Eventim-Vorstellungsidentität werden auf genau ein Angebot reduziert.
- Gewinner ist der neueste Raw-Import nach `raw_import_created_at`, danach `raw_import_id`.
- Zusatzprodukte werden nur dann aus den public `EventOffer`-Kandidaten entfernt, wenn für dieselbe Eventim-Vorstellung ein Main-Angebot vorhanden ist.
- Gemischte `esid`-Gruppen bleiben unangetastet und werden gezählt/berichtbar gemacht, aber nicht automatisch repariert.

Damit löscht der bestehende `sync_offers!` beim nächsten Merge alte Eventim-Main-Angebote, weil sie nicht mehr in der konsolidierten Offer-Liste enthalten sind.

### 4. Offer-Metadaten verbessern

Geänderte Datei:

- `app/services/merging/sync_from_imports/event_upserter.rb`

Ergänze Eventim-spezifische Metadaten in `EventOffer#metadata`:

- `eventim_series_id`
- `eventim_series_name`
- `eventim_offer_kind`
- `raw_import_id`
- `raw_import_created_at`

Diese Metadaten helfen später bei Diagnose und Backfill-Reports. Die öffentliche Anzeige muss weiterhin aus der konsolidierten Offer-Liste kommen, nicht aus einer neuen Sonderregel im Presenter.

### 5. Backfill-/Repairer-Service

Neue Datei:

- `app/services/events/maintenance/eventim_ticket_offer_repairer.rb`

Neue/geänderte Datei:

- `lib/tasks/importing_eventim.rake`

Task:

```sh
DRY_RUN=1 bin/rails importing:eventim:repair_ticket_offers
```

Der Repairer soll denselben Consolidator wie der Merge verwenden und folgende Zähler ausgeben:

- `checked_events`
- `updated_events`
- `created_offers`
- `removed_stale_offers`
- `ignored_auxiliary_records`
- `ambiguous_events`
- `dry_run`

Zusätzlich soll der Dry-Run nach Event-Reihe gruppieren. Dadurch sehen wir vor der echten Änderung explizit, dass Julia, Eiskönigin und We Will Rock You enthalten sind, und welche anderen Reihen betroffen wären.

Der Repairer darf keine manuellen Offers ändern.

### 6. Tests zuerst

Neue/geänderte Tests:

- `test/services/merging/sync_from_imports_test.rb`
- `test/services/importing/eventim/ticket_offer_classifier_test.rb`
- `test/services/events/maintenance/eventim_ticket_offer_repairer_test.rb`
- `test/tasks/importing_eventim_task_test.rb`
- kleine Anpassungen in Tests, die `ImportRecord.new` direkt verwenden

Testfälle:

1. Zwei Eventim-Main-Raw-Imports mit gleicher `esid`, gleicher Vorstellung und unterschiedlicher `eventid` erzeugen nach dem Merge nur ein Eventim-Offer mit der neueren `eventid`.
2. Ein bestehendes altes Eventim-Offer wird beim nächsten Merge entfernt, wenn ein neuerer Main-Raw-Import für dieselbe Vorstellung existiert.
3. Ein Eventim-Zusatzprodukt am selben Termin schlägt das Main-Angebot nicht und wird nicht öffentlich bevorzugt.
4. Unterschiedliche `esid` am selben Startzeitpunkt werden nicht automatisch zusammengelegt.
5. Der Repairer meldet im Dry-Run Änderungen, persistiert aber nichts.
6. Der Repairer ändert im echten Lauf nur Eventim-Offers und keine manuellen Offers.
7. Der Rake-Task delegiert korrekt an den Repairer und reicht `DRY_RUN` durch.

### 7. Lokale Verifikation

Nach Implementierung:

```sh
mise exec -- bin/rails test test/services/merging/sync_from_imports_test.rb
mise exec -- bin/rails test test/services/importing/eventim/ticket_offer_classifier_test.rb
mise exec -- bin/rails test test/services/events/maintenance/eventim_ticket_offer_repairer_test.rb test/tasks/importing_eventim_task_test.rb
mise exec -- bundle exec rubocop app/services/merging/sync_from_imports.rb app/services/merging/sync_from_imports/record_builders/base.rb app/services/merging/sync_from_imports/event_upserter.rb app/services/merging/sync_from_imports/eventim_offer_consolidator.rb app/services/importing/eventim/ticket_offer_classifier.rb app/services/events/maintenance/eventim_ticket_offer_repairer.rb lib/tasks/importing_eventim.rake
mise exec -- bin/ci
```

### 8. Produktions-Verifikation nach Deployment

1. Dry-Run ausführen:

   ```sh
   mise exec -- bin/kamal app exec --reuse "DRY_RUN=1 bin/rails importing:eventim:repair_ticket_offers"
   ```

2. Dry-Run prüfen:

   - Julia muss in der Zusammenfassung erscheinen.
   - Eiskönigin und We Will Rock You müssen in der Zusammenfassung erscheinen.
   - Gemischte `esid`-Fälle müssen als `ambiguous` gemeldet und nicht automatisch repariert werden.
   - Zusatzprodukte dürfen nicht als Main-Gewinner auftauchen.

3. Repair ausführen:

   ```sh
   mise exec -- bin/kamal app exec --reuse "bin/rails importing:eventim:repair_ticket_offers"
   ```

4. Live prüfen:

   - Eiskönigin Beispieltermin oder nächster zukünftiger Eiskönigin-Termin zeigt die neue Eventim-ID.
   - We Will Rock You Beispieltermin oder nächster zukünftiger WWRY-Termin zeigt die neue Eventim-ID.
   - Julia Beispieltermin `2026-09-30` zeigt die neueste Main-Eventim-ID.
   - Die Zielseiten öffnen die korrekten Eventim-Eventseiten, nicht eine 404-Seite und nicht ein VIP-/Package-Produkt.

## README

Voraussichtlich keine README-Änderung, weil der Fix keine dauerhafte Bedienung, kein Setup und keine Architekturentscheidung für Anwender ändert. Falls der Rake-Task als wiederkehrendes Betriebswerkzeug dokumentiert werden soll, wird eine kurze README-Notiz im selben Change ergänzt.

## Rollout

1. Implementieren und lokal verifizieren.
2. Deployen.
3. Produktions-Dry-Run prüfen.
4. Backfill ausführen.
5. Stichproben live im Browser prüfen.
6. Den nächsten regulären Merge-Lauf beobachten. Danach sollten dieselben Eventim-ID-Wechsel nicht wieder auftreten.

## Restrisiko

Das Problem kann künftig wieder auftreten, wenn Eventim neue Zusatzprodukt-Bezeichnungen liefert, die der Classifier noch nicht erkennt. Der Fix reduziert dieses Risiko deutlich, weil echte ID-Wechsel über `esid + start_at + venue + newest raw import` behandelt werden. Neue, bisher unbekannte Zusatzproduktmuster müssen über Dry-Run-/Ambiguous-Ausgaben auffallen und dann gezielt ergänzt werden.
