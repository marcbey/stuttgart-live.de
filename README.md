# stuttgart-live.de

`stuttgart-live.de` ist ein lokales Stadtmagazin für Veranstaltungen, Kultur und Freizeittipps in Stuttgart. Die Anwendung sammelt Termine aus verschiedenen Quellen, führt sie redaktionell zusammen und veröffentlicht sie in einer schnellen, klaren Oberfläche.

Das Repository enthält die komplette Anwendung: öffentliche Website, redaktionelles Backend, Importlogik, Hintergrundjobs und die wichtigsten Deploy- und Betriebsbausteine.

## Kurzüberblick

- Ruby 4.0.2
- Ruby on Rails 8.1
- PostgreSQL
- Hotwire mit Turbo und Stimulus
- Tailwind CSS 4 und esbuild
- Active Storage und Action Text
- Solid Queue, Solid Cache und Solid Cable
- Deployment mit Kamal auf Hetzner
- Tests mit Minitest, Capybara und Selenium

Die App ist bewusst ein klassischer Rails-Monolith. Das hält die Komplexität niedrig und sorgt dafür, dass redaktionelle Abläufe, Importe und öffentliche Ausgabe auf demselben Domänenmodell arbeiten.

## Was die Anwendung abdeckt

- Öffentliche Website mit Event-Listen, Event-Detailseiten, News und statischen Inhaltsseiten
- Redaktionelles Backend für Events, Bilder, Blog, Benutzer und Importquellen
- Import-Pipeline für externe Anbieter wie Easyticket, Eventim und Reservix
- Redaktionelle Qualitätssicherung mit Inbox, Änderungsprotokollen und Vollständigkeitsprüfungen
- Newsletter-Anmeldung mit optionalem Mailchimp-Sync

## Wie das System grob funktioniert

Ein typischer Ablauf für Events sieht so aus:

1. Externe Quellen liefern Rohdaten.
2. Importläufe holen diese Daten in die Anwendung.
3. Services gleichen Dubletten und Änderungen ab.
4. Die Redaktion prüft, ergänzt und veröffentlicht die Inhalte im Backend.
5. Öffentliche Seiten lesen die freigegebenen Daten aus und zeigen sie Besucherinnen und Besuchern an.

Wichtige fachliche Bausteine sind dabei:

- `Event` als zentrales Veröffentlichungsmodell
- `EventImage`, `EventOffer` und `EventChangeLog` für ergänzende Event-Daten
- `ImportSource`, `ImportRun` und `RawEventImport` für Rohdaten, Importläufe und Laufprotokolle
- `EventLlmEnrichment` und `LlmGenreGroupingSnapshot` für nachgelagerte LLM-basierte Qualitäts- und Strukturierungsschritte
- `BlogPost` für redaktionelle Inhalte
- `NewsletterSubscriber` für Newsletter-Anmeldungen

## Wie die Importer funktionieren

Die Import-Pipeline arbeitet bewusst zweistufig:

1. Die Provider-Importer holen Rohdaten von den externen Quellen und speichern sie in `raw_event_imports`.
2. Der Merge-Import liest diese Rohimporte, führt Dubletten providerübergreifend zusammen und schreibt daraus `events`, `event_offers` und `event_images`.

Dadurch bleiben die gelieferten Quelldaten nachvollziehbar gespeichert, während das öffentliche Event-Modell trotzdem nur einen bereinigten zusammengeführten Datensatz pro Termin bekommt.

### Gemeinsames Verhalten aller Provider-Importer

Easyticket, Eventim und Reservix folgen demselben Grundmuster:

- Jeder Lauf erzeugt einen `ImportRun` mit Zählern für `fetched`, `filtered`, `imported`, `upserted` und `failed`.
- Vor dem eigentlichen Start werden hängengebliebene alte Läufe derselben Quelle automatisch als fehlgeschlagen oder abgebrochen markiert.
- Jeder Importer prüft eine konfigurierbare Orts-Whitelist aus der jeweiligen `ImportSource`.
- Treffer außerhalb der Whitelist werden nicht importiert; die dabei gesehenen Städte werden im Run-Metadatenblock als `filtered_out_cities` festgehalten.
- Pro Quelldatensatz wird ein `RawEventImport` angelegt. Das ist absichtlich append-only: Die Rohhistorie bleibt erhalten, statt ältere Zeilen zu überschreiben.
- Fehler einzelner Datensätze landen in `import_run_errors`, ohne den kompletten Lauf sofort abzubrechen.

Die Run-Koordination ist bewusst generisch über `ImportRun`, `source_type` und Registry-Konfiguration aufgebaut. Je nach Jobtyp laufen Jobs exklusiv oder als serielle Warteschlange. Das LLM-Enrichment nutzt diese Infrastruktur bereits: Es gibt dort immer höchstens einen aktiven Lauf, weitere Anforderungen werden als `queued` eingereiht.

Für den täglichen Betrieb startet `Importing::DailyRunJob` die aktiven Provider standardmäßig über `config/recurring.yml` jeden Tag um `03:05` Uhr. Manuell lassen sich die Läufe im Backend unter den Importquellen oder per Rake-Task starten:

```bash
bin/rake importing:easyticket:run
bin/rake importing:eventim:run
bin/rake importing:reservix:run
```

### Easyticket

Der Easyticket-Importer lädt zunächst einen Event-Dump und verarbeitet anschließend jeden Datensatz einzeln. Wenn im Dump noch keine brauchbaren Bildkandidaten enthalten sind, wird zusätzlich ein Detail-Request ausgeführt und als `detail_payload` am `RawEventImport` gespeichert. Als eindeutige Rohimport-ID dient im Regelfall `event_id:datum`, damit unterschiedliche Termine desselben Events getrennt bleiben.

### Eventim

Der Eventim-Importer verarbeitet den Feed streamend. Dadurch muss nicht erst die komplette Quelle im Speicher liegen, bevor der Lauf beginnen kann. Auch hier wird pro passendem Feed-Eintrag ein `RawEventImport` geschrieben; die `source_identifier` setzt sich typischerweise aus externer Event-ID und Datum zusammen.

### Reservix

Der Reservix-Importer arbeitet inkrementell. Er merkt sich in der `ImportSourceConfig` einen Checkpoint aus `lastupdate` und der zuletzt verarbeiteten Event-ID. Der nächste Lauf fragt die API mit leichtem Zeitüberlapp erneut ab, überspringt aber bereits bekannte Datensätze anhand dieses Checkpoints. Zusätzlich werden nur buchbare Events übernommen.

### Wie der Merge-Import funktioniert

Der Merge-Import ist der zweite Schritt nach den Provider-Läufen. Er wird im Backend über "Importierte Events synchronisieren" gestartet und läuft technisch als eigener `ImportRun` mit `source_type = "merge"`.

Der Ablauf ist:

1. Zuerst wird je Quelle nur der aktuellste `RawEventImport` pro `source_identifier` berücksichtigt.
2. Daraus baut `Merging::SyncFromImports::RecordBuilder` normierte Import-Records mit vereinheitlichten Feldern wie Artist, Titel, Startzeit, Venue, Preisen, Links und Bildern.
3. Diese Records werden providerübergreifend über einen Dublettenschlüssel gruppiert. Der Schlüssel besteht aus normalisiertem Artist-Namen und Startzeit.
4. Innerhalb einer Gruppe gilt eine Provider-Priorität. Höher priorisierte Quellen liefern bevorzugt die führenden Feldwerte; zusätzliche Ticketangebote und Bilder aus den anderen Quellen bleiben trotzdem erhalten.
5. `EventUpserter` sucht zuerst ein bestehendes `Event` über `source_fingerprint` oder den gespeicherten `source_snapshot`. Falls nichts passt, wird ein neues Event angelegt.
6. Danach werden `event_offers`, Genres und Bilder synchronisiert und ein Änderungslog mit `merged_create` oder `merged_update` geschrieben.
7. Nach einem erfolgreichen Merge wird automatisch ein LLM-Enrichment-Lauf eingereiht. Läuft bereits ein Enrichment, wartet der neue Lauf als `queued` in derselben seriellen Queue.

Zusätzlich zum exakten Dublettenschlüssel gibt es ein optionales Ähnlichkeits-Matching für Artist-Namen bei exakt gleicher Startzeit. Damit kann der Merge-Import auch Fälle wie `Vier Pianisten - Ein Konzert` und `Vier Pianisten` oder `Gregory Porter & Orchestra` und `Gregory Porter` als denselben Termin erkennen. Dieses Verhalten lässt sich im Backend unter `Einstellungen` über das Setting `Ähnlichkeits-Matching für Artist-Dubletten` ein- oder ausschalten.

Wichtig für das Verhalten im Backend:

- Neue oder aktualisierte automatisch gemergte Events werden nur dann direkt veröffentlicht, wenn die Pflichtfelder inklusive Bild vorhanden sind.
- Fehlen dafür wichtige Informationen, landet das Event stattdessen in `needs_review`.
- Bereits automatisch veröffentlichte Events fallen ebenfalls zurück auf `needs_review`, wenn sie nach einem späteren Merge nicht mehr vollständig genug sind.
- Der Button zum Starten des Merge-Imports wird im Backend hervorgehoben, sobald seit dem letzten erfolgreichen Merge neue erfolgreiche Provider-Imports vorliegen.
- Ein erfolgreicher Merge reiht standardmäßig direkt das LLM-Enrichment ein, damit neue oder geänderte Events ohne zusätzlichen manuellen Schritt für die nächste Qualitätsstufe bereitstehen.

Wichtig für Updates bestehender Events:

- Bei jedem Merge-Update werden `start_at`, `doors_at`, `venue`, `badge_text`, `min_price`, `max_price`, `primary_source`, `source_fingerprint` und `source_snapshot` neu aus den aktuellen Importdaten gesetzt.
- `primary_source` bleibt bei bereits zusammengeführten Events auf der höchst priorisierten vorhandenen Quelle. Standardmäßig gilt dabei `easyticket` vor `eventim` vor `reservix`.
- `source_snapshot` wird quellenübergreifend zusammengeführt, statt bei späteren Merges nur noch den zuletzt verarbeiteten Provider zu enthalten.
- `event_offers` werden quellenweise auf den aktuellen Importstand synchronisiert: bestehende passende Offers werden aktualisiert, neue angelegt und nur Offers derselben gerade verarbeiteten Quelle entfernt, wenn sie dort nicht mehr vorkommen.
- Bilder werden ebenfalls quellenweise auf den aktuellen Merge-Stand synchronisiert.
- `title`, `artist_name`, `city`, `promoter_id`, `youtube_url`, `homepage_url`, `facebook_url` und `event_info` werden bei einem bestehenden Event durch den Merge nicht überschrieben. Diese Felder werden nur beim erstmaligen Anlegen aus den Importdaten vorbelegt.
- Manuelle redaktionelle Änderungen an genau diesen nicht überschriebenen Feldern bleiben bei späteren Merge-Läufen deshalb erhalten.

Der Merge kann außerdem inkrementell auf Basis eines Zeitpunkts laufen. In diesem Fall werden nur Fingerprints neu gebaut, die seit `last_run_at` von neuen Rohimporten berührt wurden; für diese Gruppen wird aber jeweils wieder der aktuelle Gesamtstand aller Quellen zusammengeführt.

### Wie Event-Reihen funktionieren

Zusätzlich zum eigentlichen Termin-Merge kennt die Anwendung das separate fachliche Konzept `EventSeries`. Eine Event-Reihe gruppiert mehrere logisch zusammengehörige Events, ohne sie zu einem einzelnen Termin zusammenzuführen. Das ist bewusst unabhängig vom Dubletten-Merge: Der Merge beantwortet die Frage "Sind das dieselben Termine aus verschiedenen Quellen?", die Event-Reihe beantwortet die Frage "Gehören mehrere unterschiedliche Termine inhaltlich zusammen?".

Technisch besteht das Modell aus:

- `event_series` als eigene Tabelle mit `origin`, optionalem `name` sowie bei importierten Reihen `source_type` und `source_key`
- `events.event_series_id` als optionale Zuordnung eines Events zu genau einer Event-Reihe
- `events.event_series_assignment` zur Unterscheidung zwischen automatischer Import-Zuordnung (`auto`) und redaktionellen Entscheidungen (`manual`, `manual_none`)

Fachlich wichtig:

- Eine Event-Reihe kann importiert oder manuell angelegt sein.
- Ein Event kann höchstens einer Event-Reihe gleichzeitig zugeordnet sein.
- Event-Reihen werden gelöscht, wenn ihnen nach einer Änderung gar kein Event mehr zugeordnet ist.
- Die Existenz einer gespeicherten Event-Reihe und ihre öffentliche Wirkung sind bewusst nicht dasselbe.

### Wie Importer Event-Reihen erkennen

Die automatische Erkennung passiert schon beim Rohimport. Der Importer versucht dabei nicht, freie Heuristiken über Titel oder Artist-Namen abzuleiten, sondern übernimmt nur explizite Provider-Signale.

Aktuell gilt:

- `Eventim`: Wenn der Feed `esid` liefert, wird dieser Wert als stabiler Reihen-Schlüssel verwendet. `esname` dient als Reihenname. Der `eventserie`-Kontext aus dem Feed wird beim Expandieren auf die einzelnen Termine mitgenommen.
- `Reservix`: Wenn im Payload `references.eventgroup[].id` vorhanden ist, wird diese ID als Reihen-Schlüssel verwendet. `references.eventgroup[].name` wird als Reihenname übernommen.
- `Easyticket`: Der Importer legt derzeit keine automatischen Event-Reihen an, weil dort noch kein gleichwertiges explizites Gruppenfeld genutzt wird.

Die Provider-Signale werden zunächst als `Importing::EventSeriesReference` normalisiert. `EventSeriesResolver` sorgt dann dafür, dass für einen gegebenen provider-spezifischen Schlüssel genau eine importierte `EventSeries` existiert.

Wichtig für die Einordnung:

- Eventim-Signale sind derzeit meist sehr stabil, aber in der Praxis sehr häufig vorhanden. Nicht jedes so erkannte Bündel ist automatisch eine redaktionell sinnvolle "Reihe" im engeren Sinn.
- Reservix-`eventgroup` ist fachlich unzuverlässiger. In manchen Fällen verhält sich dieses Feld eher wie ein Veranstalter- oder Container-Schlüssel als wie eine echte Reihe. Die Zuordnung bleibt deshalb technisch nachvollziehbar, muss redaktionell aber kritisch betrachtet werden.

### Wie der Merge Event-Reihen persistiert

Beim Merge wird die Serien-Referenz aus den aktuellen Rohimporten erneut gelesen und an das kanonische `Event` gehängt. Die Event-Reihe ist damit Teil des regulären Merge-Stands, ähnlich wie `source_snapshot`, `primary_source` oder Ticket-Offers.

Die Regeln dafür sind:

- Ist in den aktuellen Import-Records eine Reihen-Referenz vorhanden, wird das Event dieser `EventSeries` zugeordnet.
- Ist keine Reihen-Referenz mehr vorhanden und das Event hing bisher an einer importierten Reihe, wird die Zuordnung entfernt.
- Manuelle redaktionelle Entscheidungen haben Vorrang: Sobald ein Event `event_series_assignment = manual` oder `manual_none` hat, überschreibt der Merge diese Serien-Entscheidung nicht mehr.
- Im `source_snapshot` wird die aktuelle Serien-Herkunft mitgespeichert, damit später nachvollziehbar bleibt, aus welchem Provider-Signal die Zuordnung stammt.

Dadurch bleiben folgende Fälle sauber getrennt:

- automatische Import-Zuordnung zu einer erkannten Reihe
- manuelle redaktionelle Umgruppierung in eine andere Reihe
- manuelles bewusstes Herauslösen aus einer importierten Reihe

### Wie die Redaktion Event-Reihen im Backend verwaltet

Im Backend lassen sich Event-Reihen über die Event-Liste manuell pflegen. Die bestehende Filterung und Mehrfachauswahl ist dabei der primäre Arbeitsweg.

Die wichtigsten Abläufe sind:

- Bulk-Aktion `Als Event-Reihe zusammenfassen`: legt eine neue manuelle `EventSeries` an und ordnet alle ausgewählten Events dieser Reihe zu
- Bulk-Aktion `Aus Event-Reihe lösen`: entfernt die ausgewählten Events wieder aus ihrer aktuellen Reihe
- leere Reihen werden bei solchen Änderungen automatisch bereinigt

Die Herkunft einer Reihe bleibt sichtbar:

- importierte Reihen kommen aus den Provider-Signalen
- manuelle Reihen stammen aus der redaktionellen Bulk-Aktion

Für die Badge-Logik im Backend gilt bewusst eine redaktionelle Regel:

- In `events_list` und im Event-Editor wird `Event-Reihe` angezeigt, wenn zur `event_series_id` insgesamt mindestens zwei Events im Datenbestand existieren.
- Dabei wird nicht nach `published`, `published_at` oder Vergangenheit/Zukunft gefiltert.
- Das Backend bewertet also die gespeicherte redaktionelle Struktur, nicht die öffentliche Sichtbarkeit.

### Wie Event-Reihen im Frontend wirken

Im öffentlichen Frontend gilt eine strengere, sichtbarkeitsbezogene Regel als im Backend. Eine Event-Reihe ist dort nur wirksam, wenn sie in der gesamten öffentlich sichtbaren Event-Menge tatsächlich mindestens zwei Events hat.

Öffentlich sichtbar bedeutet:

- `status = published`
- `published_at <= jetzt`

Dabei zählen ausdrücklich auch vergangene veröffentlichte Events mit. Die Frontend-Regel ist also global über den öffentlichen Bestand und nicht mehr auf die lokale Quellmenge einer einzelnen Lane beschränkt.

Die konkreten Auswirkungen sind:

- Karten und Listen-Items bekommen die Banderole `Event-Reihe`, wenn ihre `event_series_id` öffentlich wirksam ist.
- Homepage-Lanes wie Highlights, `Alle Veranstaltungen in Stuttgart`, `Tagestipp` und die Genre-Lanes deduplizieren Event-Reihen auf einen Repräsentanten, verwenden für die Badge-Entscheidung aber die globale öffentliche Wirksamkeit der Reihe.
- Die Related-Genre-Lane auf der Event-Detailseite folgt derselben globalen Frontend-Regel.
- Die dedizierte Event-Reihen-Lane auf der Event-Detailseite zeigt alle veröffentlichten sichtbaren Events derselben Reihe, inklusive vergangener Termine, chronologisch sortiert.

Wichtig ist der Unterschied zwischen gespeicherter Zuordnung und öffentlicher Wirkung:

- Eine importierte oder manuell angelegte Event-Reihe kann im Datenmodell existieren, obwohl öffentlich aktuell nur ein einziges sichtbares Event dazugehört.
- In diesem Fall bleibt die Zuordnung im Backend sichtbar, im Frontend erscheint aber keine `Event-Reihe`-Banderole.
- Sobald ein zweites veröffentlichtes sichtbares Event derselben Reihe vorhanden ist, wird die Reihe ohne weitere Redaktion automatisch auch öffentlich wirksam.

### Wie das LLM-Enrichment funktioniert

Das LLM-Enrichment läuft auf bereits gemergten `events` und ist damit bewusst ein nachgelagerter Qualitätsschritt. Es erzeugt keine neuen Events und verändert keine Rohimporte, sondern ergänzt vorhandene Datensätze um zusätzliche redaktionelle Informationen.

Der Ablauf ist:

1. Zuerst wählt der Job geeignete bestehende Events aus, typischerweise solche ohne vollständige LLM-Anreicherung oder mit veralteten Enrichment-Daten.
2. Diese Events werden in Batches an das konfigurierte LLM-Modell geschickt.
3. Die Antwort wird validiert, normalisiert und als `event_llm_enrichments` am jeweiligen Event gespeichert.
4. Der Lauf protokolliert Auswahlmenge, übersprungene Events, erfolgreiche Enrichments, Batch-Zahl und Fehler im zugehörigen `ImportRun`.

Fachlich ist wichtig:

- Das Enrichment arbeitet auf dem bestehenden Event-Bestand nach dem Merge.
- Erfolgreiche Merge-Läufe reihen immer einen Enrichment-Run ein. Wenn bereits ein Enrichment läuft oder schon wartet, wird der neue Lauf seriell hinten angehängt.
- Im Event-Editor kann zusätzlich ein manueller LLM-Enrichment-Lauf für genau ein einzelnes gespeichertes Event gestartet werden. Dieser Lauf überschreibt vorhandene Enrichment-Daten bewusst und reiht sich ebenfalls seriell in die bestehende LLM-Queue ein.
- Es dient der redaktionellen Verdichtung, nicht der Dubletten-Erkennung.
- Modellname und Prompt-Vorlage werden über `app_settings` im Backend konfiguriert.
- Fehlerhafte Einzelantworten sollen im Laufprotokoll sichtbar sein, ohne zwangsläufig den kompletten Prozess unbrauchbar zu machen.

Im Backend spiegeln die Run-Status dabei die fachliche Koordination wider:

- `queued`: Der Lauf ist angelegt und wartet auf seinen Platz in der seriellen Queue.
- `running`: Der Worker hat den Lauf übernommen und verarbeitet ihn aktiv.
- `stopping`: Für einen laufenden Run wurde ein kooperativer Stop angefordert.
- `canceled`: Der Lauf wurde vor oder während der Verarbeitung beendet.
- `failed`: Der Lauf ist mit einem Fehler oder Timeout beendet worden.

Queued LLM-Enrichment-Runs lassen sich im Backend abbrechen, bevor sie gestartet werden. Der nächste wartende Run rückt dann automatisch nach.

Für Merge-, Provider- und LLM-Läufe gilt außerdem: Wenn ein Run nach einem Stop-Wunsch oder allgemein nach Start über seine Heartbeat-/Stale-Timeouts hinaus keine Fortschrittsupdates mehr schreibt, wird er beim nächsten Aufruf der Importer-Übersicht automatisch freigegeben statt dauerhaft auf `running` oder `stopping` zu hängen.

### Wie die LLM-Genre-Gruppierung funktioniert

Die LLM-Genre-Gruppierung ist ein eigener Schritt zur Vereinheitlichung der Genre-Landschaft im System. Sie betrachtet nicht einzelne Event-Beschreibungen, sondern die bereits vorhandenen Genre-Werte und ordnet ähnliche oder doppelte Begriffe zu größeren, konsistenten Gruppen.

Der Ablauf ist:

1. Der Job sammelt die vorhandenen Rohgenre-Werte aus dem Datenbestand.
2. Diese Werte werden normalisiert, offensichtliche Duplikate reduziert und in Requests an das konfigurierte LLM-Modell aufgeteilt.
3. Das Modell schlägt Obergruppen und Zuordnungen vor.
4. Das Ergebnis wird als `llm_genre_grouping_snapshot` mit zugehörigen Gruppen gespeichert. Jeder erfolgreiche Lauf erzeugt einen neuen Snapshot mit eigener ID.

Fachlich ist wichtig:

- Ziel ist eine stabilere, redaktionell brauchbare Genre-Struktur für Filter, Übersichten und thematische Strecken.
- Der Lauf arbeitet snapshot-basiert, damit Ergebnisse nachvollziehbar und versionierbar bleiben.
- Ein neuer erfolgreicher Lauf schaltet keinen Snapshot automatisch um. Welcher Snapshot öffentlich verwendet wird, wird separat im Backend gewählt.
- Die öffentliche Verwendung der Genre-Gruppierung ist global an einen ausgewählten Snapshot gebunden. Das betrifft die Homepage-Genre-Lanes, die Genre-Obergruppe im Event-Detail und die Related-Genre-Lane.
- Die Lane-Auswahl auf der Startseite wird pro Snapshot gespeichert. Ein Wechsel des ausgewählten Snapshots im Backend zeigt deshalb seine eigene gespeicherte Lane-Konfiguration.
- Modell, Prompt und Zielanzahl der Gruppen werden über `app_settings` gesteuert.
- Die Import-Job-Tabelle zeigt bei diesem Lauf vor allem, wie viele Rohgenres verarbeitet, verworfen, gruppiert und an das LLM geschickt wurden.

### Kennzahlen in "Importer Jobs"

Im Backend zeigen die Tabellen `Importer Jobs` und `Importer Job #...` absichtlich verschiedene Ebenen der Import-Pipeline. Die Spalten haben dieselbe Bedeutung wie die Hover-Texte im UI:

- `Raw Imports`: Provider-Importer zeigen hier die Anzahl der in diesem Lauf geschriebenen `RawEventImport`-Zeilen. Beim Merge ist es die Anzahl der aktuellen normierten Import-Records nach Auswahl des neuesten Rohimports je `source_identifier`. Beim LLM-Genre-Gruppierungsjob ist es die Anzahl der eindeutigen LLM-Genres, die in diesem Lauf gruppiert wurden.
- `Merge Groups`: Nur beim Merge befüllt. Zeigt, wie viele providerübergreifende Gruppen nach Dublettenzusammenführung über normalisierten Artist-Namen und Startzeit entstanden sind.
- `Filtered`: Nur bei Provider-Läufen befüllt. Zeigt, wie viele Quelldatensätze die Orts- und Importfilter passiert haben. Beim LLM-Genre-Gruppierungsjob ist es die Anzahl verworfener Rohgenre-Werte nach Normalisierung.
- `Inserts`: Bei Provider-Läufen entspricht das den geschriebenen Rohimporten dieses Laufs. Beim Merge ist es die Anzahl neu angelegter `Event`-Datensätze. Beim LLM-Genre-Gruppierungsjob ist es die Anzahl gespeicherter Obergruppen.
- `Updates`: Nur beim Merge befüllt. Zählt bestehende `Event`-Datensätze, die in diesem Lauf aktualisiert wurden. Dabei überschreibt der Merge `start_at`, `doors_at`, `venue`, `badge_text`, `min_price`, `max_price`, `primary_source`, `source_fingerprint` und `source_snapshot`.
- `Similarity Duplicates`: Nur beim Merge befüllt. Das ist keine zusätzliche dritte Menge neben `Inserts` und `Updates`, sondern eine Teilmenge der `Updates`. Gezählt werden nur Fälle, in denen das Ähnlichkeits-Matching einen Import-Record einem bestehenden Event zuordnet.
- `Collapsed Records`: Nur beim Merge befüllt. Das ist `Raw Imports - Merge Groups` und zeigt, wie viele aktuelle Rohimporte schon vor dem finalen Event-Upsert zu gemeinsamen Merge-Gruppen zusammengefasst wurden. Beim LLM-Genre-Gruppierungsjob ist es die Anzahl der an OpenAI gesendeten Requests.

Wichtig für die Interpretation:

- Die Summen der Provider-Läufe sind nicht direkt mit `Inserts + Updates` aus dem Merge vergleichbar.
- Gründe dafür sind erstens mehrere Rohimporte derselben Quelle mit identischem `source_identifier`, von denen im Merge nur die jeweils neueste Version berücksichtigt wird, und zweitens die providerübergreifende Gruppierung mehrerer Quellen auf denselben Termin.
- `Similarity Duplicates` sind bereits in `Updates` enthalten und dürfen deshalb nicht zusätzlich aufaddiert werden.
- Der angezeigte Status eines Jobs ist nicht nur ein Active-Job-Snapshot, sondern Teil der fachlichen Run-Koordination. Besonders bei LLM-Enrichment zeigen `queued`, `running` und `stopping`, wie mehrere Anforderungen seriell über dieselbe Import-Queue abgearbeitet werden.

## Wo man im Code typischerweise hinschaut

- `app/controllers/public` für öffentliche Seiten
- `app/controllers/backend` für Redaktion und Administration
- `app/models` für Domänenlogik und Persistenz
- `app/services` für fachliche Abläufe wie Import, Merge, Blog und Newsletter
- `app/queries` für Listen- und Lesezugriffe
- `app/jobs` für Hintergrundverarbeitung
- `app/javascript/controllers` für Stimulus-Verhalten
- `lib/tasks` für operative Rake-Tasks

## Lokal entwickeln

### Voraussetzungen

- Ruby 4.0.2 in der Projektversion
- PostgreSQL
- Node.js und npm

Für die lokale Entwicklung und für den Produktionscontainer gilt dieselbe Ruby-Version. Kamal rollt die App als Docker-Image aus; der Produktionshost selbst braucht deshalb kein separates systemweites Ruby 4.

### Schnellstart

```bash
bin/setup
bin/dev
```

`bin/dev` startet die lokale Entwicklungsumgebung mit Rails, Job-Verarbeitung sowie JavaScript- und CSS-Watchern.

### Wichtige Kommandos

```bash
bin/rails test
bin/rails console
bin/rake -T
bin/ci
```

## Wichtige Konfiguration

Nicht jede Variable wird in jeder Umgebung gebraucht. Für den Alltag sind diese Gruppen wichtig:

- `config/credentials.yml.enc`: `EASYTICKET_*`, `EVENTIM_USER`, `EVENTIM_PASS`, `EVENTIM_FEED_KEY`, `RESERVIX_API_KEY`, `RESERVIX_EVENTS_API`, `MAILCHIMP_*`, `SMTP_*`
- statisch im Code: `GOOGLE_ANALYTICS_ID`, `MAILER_FROM`
- `config/deploy.hetzner.shared.yml`: `APP_HOST`, `KAMAL_WEB_HOST`, `KAMAL_SSH_HOST_KEY`
- lokale `.env`: `DB_PASSWORD`, `KAMAL_REGISTRY_PULL_PASSWORD`, optional `HCLOUD_TOKEN` für Hetzner-Terraform
- lokale Datei `config/master.key`: Schlüssel für `config/credentials.yml.enc`
- GitHub-Secrets für Deployments: `DB_PASSWORD`, `RAILS_MASTER_KEY`, `KAMAL_REGISTRY_PULL_PASSWORD`, `KAMAL_SSH_PRIVATE_KEY`

Ohne Mailchimp-Konfiguration funktioniert die lokale Speicherung von Newsletter-Anmeldungen weiterhin, nur der externe Sync bleibt aus.

Zusätzlich gibt es Laufzeitkonfiguration in der Datenbank über `app_settings`. Diese Werte werden im Admin-Bereich unter `Einstellungen` gepflegt und sind bewusst nicht in Credentials oder Umgebungsvariablen abgelegt. Aktuell liegen dort unter anderem:

- `sks_promoter_ids` für SKS-Filter und Sortierung
- `sks_organizer_notes` für den Standardtext bei SKS-Events ohne eigene Veranstalterhinweise
- `llm_enrichment_model` und `llm_enrichment_prompt_template` für den Enrichment-Job
- `llm_genre_grouping_model`, `llm_genre_grouping_prompt_template` und `llm_genre_grouping_group_count` für den Genre-Gruppierungsjob
- `public_genre_grouping_snapshot_id` für den global öffentlich verwendeten Genre-Snapshot
- `merge_artist_similarity_matching_enabled` für das quellenübergreifende Ähnlichkeits-Matching von Artist-Namen im Merge-Import bei exakt gleicher Startzeit

### Typische Arbeitsweisen

Mit der aktuellen Struktur gibt es vier übliche Betriebsmodi:

- lokale Entwicklung: Rails liest App-Konfiguration aus `config/credentials.yml.enc`; dafür braucht die App vor allem `config/master.key`
- lokale Hetzner-Infrastruktur: Terraform nutzt lokal `HCLOUD_TOKEN`, typischerweise aus `.env` oder der Shell
- lokaler Produktions-Deploy: Kamal nutzt lokal `DB_PASSWORD` und `KAMAL_REGISTRY_PULL_PASSWORD` aus `.env` sowie `config/master.key`
- GitHub-Produktions-Deploy: GitHub Actions nutzt `DB_PASSWORD`, `RAILS_MASTER_KEY`, `KAMAL_REGISTRY_PULL_PASSWORD` und `KAMAL_SSH_PRIVATE_KEY` aus GitHub-Secrets

Wenn du lokal sowohl entwickelst als auch Hetzner-Infrastruktur steuerst und manuell nach Produktion deployen willst, reicht aktuell in `.env` in der Regel:

```dotenv
DB_PASSWORD=...
HCLOUD_TOKEN=...
KAMAL_REGISTRY_PULL_PASSWORD=...
```

## Qualitätssicherung

Der Standardweg für Prüfungen ist:

```bash
bin/ci
```

`bin/ci` bündelt Setup, Linting, Security-Checks und Tests. Die Rails-Tests laufen dort mit aktiviertem Bullet, damit N+1-Queries den Lauf fehlschlagen lassen. Vor einem Push sollte dieser Lauf grün sein.

Wenn du Bullet lokal gezielt im Testlauf aktivieren willst:

```bash
BULLET=1 bin/rails test
```

## Deployment und Betrieb

Produktion läuft auf Hetzner und wird mit Kamal ausgerollt. Im Alltag gibt es zwei Wege:

- automatische Deployments über GitHub Actions nach Pushes auf `main`
- manuelle Eingriffe von lokal per `bin/kamal ... -d hetzner`

Webprozess und Job-Verarbeitung laufen gemeinsam in der Rails-Anwendung. `SOLID_QUEUE_IN_PUMA=true` ist für dieses Setup bereits vorgesehen.

Die produktive öffentliche Domain, die Ziel-IP und der gepinnte SSH-Host-Key stehen versioniert in [config/deploy.hetzner.shared.yml](/Users/marc/Projects/stuttgart-live.de/config/deploy.hetzner.shared.yml).
Die Datei bleibt bewusst außerhalb des Docker-Build-Kontexts; Kamal setzt `APP_HOST` daraus zur Laufzeit in den Produktions-Container.

### Was lokal wichtig ist

Für manuelle Produktions-Kommandos brauchst du lokal:

- `config/master.key`
- die versionierte Datei `config/deploy.hetzner.shared.yml`
- eine lokale `.kamal/secrets.hetzner`
- den SSH-Key `~/.ssh/stgt-live-hetzner-github` für den Benutzer `deploy`
- optional den SSH-Key `~/.ssh/stgt-live-hetzner-admin` für Host-Administration als `admin`
- eine `.env` mit `DB_PASSWORD` und `KAMAL_REGISTRY_PULL_PASSWORD`

Der aktuell konfigurierte Zielhost ist `46.225.224.194`.

Vor manuellen Kamal-Eingriffen sollte immer dieser Check laufen:

```bash
bin/hetzner-check
```

Das Skript liest die versionierte Hetzner-Konfiguration, prüft die lokalen SSH-Keys sowie die Vollständigkeit von `.kamal/secrets.hetzner` gegen `config/deploy.hetzner.yml` und bricht bei Abweichungen sofort ab.

Wichtig: Die lokale `.kamal/secrets.hetzner` ist hier keine Klartext-Secret-Datei. Sie ist ignoriert und löst nur die Deploy-Secrets aus `.env` und `config/master.key` auf. Die App-Konfiguration für Importer, Newsletter und SMTP kommt aus `config/credentials.yml.enc`. Als Vorlage dient `.kamal/secrets.hetzner.example`.

GitHub Actions nutzt diese lokale Datei nicht. Der Workflow erzeugt zur Laufzeit eine eigene `.kamal/secrets.hetzner` aus den in GitHub hinterlegten Secrets.

### Automatischer Deploy über GitHub

Der GitHub-Workflow liest `APP_HOST`, `KAMAL_WEB_HOST` und `KAMAL_SSH_HOST_KEY` direkt aus der versionierten Datei `config/deploy.hetzner.shared.yml`.
Ruby wird in CI und Deploy explizit aus `.ruby-version` geladen; aktuell ist das `4.0.2`.
Vor dem eigentlichen App-Deploy prüft der Workflow außerdem die Version von `kamal-proxy` auf dem Zielhost und führt bei Bedarf automatisch `bin/kamal proxy reboot -d hetzner` aus.
Hintergrund: Seit `kamal 2.11.0` ist `kamal-proxy v0.9.2` oder neuer für Deployments erforderlich.

In GitHub müssen deshalb nur diese Secrets gepflegt sein:

- `DB_PASSWORD`
- `RAILS_MASTER_KEY`
- `KAMAL_REGISTRY_PULL_PASSWORD`
- `KAMAL_SSH_PRIVATE_KEY`

Nicht-geheime Zielwerte für Domain, Server-IP und gepinnten SSH-Host-Key werden nicht mehr als GitHub-Variablen gepflegt.

### Die wichtigsten Kommandos

Deployment von lokal:

```bash
bin/hetzner-check
bin/kamal deploy -d hetzner
bin/hetzner-check
bin/kamal redeploy -d hetzner
bin/hetzner-check
bin/kamal rollback <VERSION> -d hetzner
```

Status und Logs:

```bash
bin/kamal details -d hetzner
bin/kamal proxy reboot -d hetzner
bin/kamal app containers -d hetzner
bin/kamal app version -d hetzner
bin/kamal app logs -f -d hetzner
bin/kamal app logs --since 15m -d hetzner
bin/kamal app logs --since 30m --grep ERROR -d hetzner
```

Der Produktions-Logpfad für App und Jobs ist bewusst zentral über Docker/Kamal organisiert. Rails schreibt in Production nach `STDOUT`, daher sind `bin/kamal app logs ...` und auf dem Host `docker logs ...` die primären Werkzeuge auch für Import- und LLM-Läufe.

Es gibt in Produktion absichtlich keinen separaten persistenten App-Dateilog unter `log/production.log` oder `log/importers.log`. Wenn später Sentry dazukommt, ergänzt es Fehlererfassung und Alerting, ersetzt aber nicht diese zentralen Laufzeit-Logs.

Rails-Konsole, Shell und Tasks im laufenden Container:

```bash
bin/hetzner-check
bin/kamal app exec --interactive --reuse "bin/rails console" -d hetzner
bin/hetzner-check
bin/kamal app exec --interactive --reuse "bash" -d hetzner
bin/hetzner-check
bin/kamal app exec --reuse "bin/rake <namespace>:<task>" -d hetzner
bin/hetzner-check
bin/kamal app exec --reuse "bin/rails runner 'puts Event.count'" -d hetzner
bin/hetzner-check
bin/kamal app exec --reuse "bin/rails db:migrate" -d hetzner
```

`--interactive` brauchst du für Konsole und Shell. `--reuse` sorgt dafür, dass das Kommando im bereits laufenden Container statt in einem frischen Einmal-Container ausgeführt wird.

### SSH auf den Server

Für Container-nahe Eingriffe als `deploy`:

```bash
ssh -i ~/.ssh/stgt-live-hetzner-github deploy@46.225.224.194
```

Für Host-Administration als `admin`:

```bash
ssh -i ~/.ssh/stgt-live-hetzner-admin admin@46.225.224.194
```

Nützliche Host-Kommandos:

```bash
docker ps
docker logs <container_id>
docker inspect <container_id>
sudo systemctl status docker
sudo journalctl -u docker -n 200 --no-pager
```

### Datenbank und Uploads

PostgreSQL läuft direkt auf dem Host, nicht in einem separaten Container. Die App nutzt diese Datenbanken:

- `stuttgart_live_de_production`
- `stuttgart_live_de_production_cache`
- `stuttgart_live_de_production_queue`
- `stuttgart_live_de_production_cable`

Uploads liegen im Docker-Volume `stuttgart_live_de_storage`. Der Host-Pfad dafür ist üblicherweise `/var/lib/docker/volumes/stuttgart_live_de_storage/_data`. Backups liegen standardmäßig unter `/var/backups/stuttgart-live`.

Datenbankzugriff auf dem Host:

```bash
sudo -u postgres psql
sudo -u postgres psql -l
sudo -u postgres psql stuttgart_live_de_production
sudo -u postgres pg_dump stuttgart_live_de_production > /tmp/stuttgart_live_de_production.sql
```

Event-Bestand lokal leeren, ohne die Importtabellen anzufassen:

```bash
bin/rails events:maintenance:purge_all
```

Der Task löscht `events` samt Relationen und event-bezogene `import_event_images`, lässt aber `raw_event_imports` unverändert.

Kompletter lokaler Reset von Events, Importläufen, Rohimporten und Solid-Queue-Jobzustand:

```bash
bin/rails events:maintenance:purge_all_with_imports
```

Der Task leert zusätzlich `import_runs`, `import_run_errors`, `raw_event_imports` sowie die laufzeitbezogenen `solid_queue_*`-Tabellen. Importquellen, Whitelists und wiederkehrende Queue-Definitionen aus `config/recurring.yml` bleiben erhalten; Reservix-Checkpoints werden zurückgesetzt.

Gezielter Reset für LLM-Enrichment-Daten, Genre-Gruppierungs-Snapshots, die zugehörigen LLM-Läufe und passende Queue-Jobs:

```bash
bin/rails events:maintenance:reset_llm_enrichment
```

Der Task löscht alle Einträge aus `event_llm_enrichments`, `llm_genre_grouping_snapshots` und `llm_genre_grouping_groups`, entfernt die zugehörigen `import_runs` mit `source_type = "llm_enrichment"` oder `source_type = "llm_genre_grouping"` samt `import_run_errors` und räumt passende `solid_queue_jobs` inklusive ihrer Laufzeitzustände ab. Andere Importläufe und Queue-Jobs bleiben erhalten.

### Produktionsdatenbank neu aufsetzen

Ein vollständiges Neuaufsetzen der Produktionsdatenbanken ist ein Host-Eingriff und darf nicht nur als App-User per `db:setup` erfolgen. Der Datenbankbenutzer der Anwendung hat bewusst kein `CREATEDB`.

Sichere Reihenfolge:

1. App kontrolliert stoppen:

```bash
bin/hetzner-check
bin/kamal app stop -d hetzner
```

2. Datenbanken auf dem Host als `postgres` neu anlegen:

```bash
ssh -i ~/.ssh/stgt-live-hetzner-admin admin@46.225.224.194
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
DROP DATABASE IF EXISTS stuttgart_live_de_production;
DROP DATABASE IF EXISTS stuttgart_live_de_production_cache;
DROP DATABASE IF EXISTS stuttgart_live_de_production_queue;
DROP DATABASE IF EXISTS stuttgart_live_de_production_cable;
CREATE DATABASE stuttgart_live_de_production OWNER stuttgart_live_de;
CREATE DATABASE stuttgart_live_de_production_cache OWNER stuttgart_live_de;
CREATE DATABASE stuttgart_live_de_production_queue OWNER stuttgart_live_de;
CREATE DATABASE stuttgart_live_de_production_cable OWNER stuttgart_live_de;
SQL
exit
```

3. Schema und Seeds aus der App laden:

```bash
bin/hetzner-check
bin/kamal app exec -d hetzner -- bin/rails db:schema:load db:seed
```

4. Vorherigen Release-Container oder einen frischen Deploy wieder hochfahren und prüfen:

```bash
bin/hetzner-check
bin/kamal app start -d hetzner --version <VERSION>
bin/kamal app logs --since 5m -d hetzner
curl -I https://stuttgart-live.schopp3r.de
```

`bin/rails db:setup` ist für dieses Produktions-Setup nicht der richtige Weg, weil das Kommando Datenbanken anlegen will.

### Wenn es Probleme gibt

Für die meisten Störungen reicht diese Reihenfolge:

1. `bin/kamal details -d hetzner` prüfen
2. `bin/kamal app logs --since 15m -d hetzner` ansehen
3. bei App-Fehlern per `bin/kamal app exec --interactive --reuse "bin/rails console" -d hetzner` in die Konsole
4. bei Host-Problemen per SSH `docker ps` und `systemctl status docker` prüfen
5. bei einem kaputten Release gezielt `bin/kamal rollback <VERSION> -d hetzner` ausführen

### Rollback-Checkliste

Ein Rollback setzt die laufende App auf eine ältere Container-Version zurück. Datenbankinhalte, Uploads und andere persistente Daten werden dabei nicht automatisch zurückgedreht.

Diese Reihenfolge ist im Ernstfall sinnvoll:

1. Prüfen, ob das Problem wirklich vom letzten Deploy kommt:

```bash
bin/kamal app logs --since 15m -d hetzner
bin/kamal app version -d hetzner
bin/kamal audit -d hetzner
```

2. Zielversion bestimmen, auf die zurückgerollt werden soll.

3. Rollback ausführen:

```bash
bin/kamal rollback <VERSION> -d hetzner
```

4. Direkt danach prüfen:

```bash
bin/kamal details -d hetzner
bin/kamal app version -d hetzner
bin/kamal app logs --since 15m -d hetzner
```

5. Wenn der Fehler durch eine Migration oder einen Datenzustand entstanden ist, zusätzlich die Datenbank separat prüfen. Ein Rollback des App-Containers macht keine Migration rückgängig.

## Weiterführende Dateien

Wenn du tiefer einsteigen willst, sind diese Dateien meist die besten Startpunkte:

- `config/routes.rb` für die fachliche Struktur der HTTP-Oberfläche
- `app/services` für zentrale Geschäftslogik
- `app/queries` für Listen- und Lesezugriffe
- `app/jobs` für Hintergrundverarbeitung
- `config/ci.rb` für den CI-Ablauf
- `config/deploy.hetzner.yml` für das Produktions-Deployment
- `HETZNER.md`, `INFRA.md` und `infra/ansible/README.md` für Infrastrukturdetails
