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
- Redaktionelles Backend für Events, Venues, statische Seiten, Bilder, Blog, Benutzer und Importquellen
- Import-Pipeline für externe Anbieter wie Easyticket, Eventim und Reservix
- Redaktionelle Qualitätssicherung mit Inbox, Änderungsprotokollen und Vollständigkeitsprüfungen
- Manuelles Social-Publishing für Event-Posts auf Facebook und Instagram
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
- `Venue` als eigener Veranstaltungsort mit Name, Beschreibung, Logo, Link und Adresse
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
- Pro Quelldatensatz wird ein `RawEventImport` angelegt. Innerhalb der aktiven Retention bleibt diese Rohhistorie append-only; ältere Rohimporte für vergangene Events werden später über tägliche Retention-Jobs bereinigt, statt beim nächsten Import überschrieben zu werden.
- Fehler einzelner Datensätze landen in `import_run_errors`, ohne den kompletten Lauf sofort abzubrechen.

Die Run-Koordination ist bewusst generisch über `ImportRun`, `source_type` und Registry-Konfiguration aufgebaut. Je nach Jobtyp laufen Jobs exklusiv oder als serielle Warteschlange. Das LLM-Enrichment nutzt diese Infrastruktur bereits: Es gibt dort immer höchstens einen aktiven Lauf, weitere Anforderungen werden als `queued` eingereiht.

Für den täglichen Betrieb startet `Importing::DailyRunJob` die aktiven Provider standardmäßig über `config/recurring.yml` jeden Tag um `03:05` Uhr. Der tägliche Merge läuft anschließend über `Merging::DailyRunJob` standardmäßig um `04:05` Uhr. Das tägliche LLM-Enrichment wird separat über `Importing::LlmEnrichment::DailyRunJob` standardmäßig um `05:05` Uhr eingereiht. Danach räumt `Events::Retention::PruneStaleUnpublishedEventsJob` um `06:05` Uhr nicht veröffentlichte Events auf, deren `start_at` länger als einen Monat zurückliegt; `Events::Retention::PrunePastRawEventImportsJob` löscht anschließend um `06:35` Uhr alte `raw_event_imports` für Events, deren normalisiertes Eventdatum länger als einen Monat vorbei ist. Historische Event-Detailseiten bleiben dabei erhalten, weil die Public-Seite aus `events` liest und der Merge die relevanten Quellinformationen in `events.source_snapshot` ablegt. Manuell lassen sich die Provider-Läufe im Backend unter den Importquellen oder per Rake-Task starten:

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

Der Merge-Import ist der zweite Schritt nach den Provider-Läufen. Er wird im Backend über "Importierte Events synchronisieren" gestartet und läuft technisch als eigener `ImportRun` mit `source_type = "merge"`. Zusätzlich ist standardmäßig ein täglicher automatischer Lauf um `04:05` Uhr (`Europe/Berlin`) konfiguriert.

Der Ablauf ist:

1. Zuerst wird je Quelle nur der aktuellste `RawEventImport` pro `source_identifier` berücksichtigt.
2. Daraus baut `Merging::SyncFromImports::RecordBuilder` normierte Import-Records mit vereinheitlichten Feldern wie Artist, Titel, Startzeit, Venue, Preisen, Links und Bildern.
3. Diese Records werden providerübergreifend über einen Dublettenschlüssel gruppiert. Der Schlüssel besteht aus normalisiertem Artist-Namen und Startzeit.
4. Innerhalb einer Gruppe gilt eine Provider-Priorität. Höher priorisierte Quellen liefern bevorzugt die führenden Feldwerte; zusätzliche Ticketangebote und Bilder aus den anderen Quellen bleiben trotzdem erhalten.
5. `EventUpserter` sucht zuerst ein bestehendes `Event` über `source_fingerprint` oder den gespeicherten `source_snapshot`. Falls nichts passt, wird ein neues Event angelegt.
6. Danach werden `event_offers`, Genres und Bilder synchronisiert und ein Änderungslog mit `merged_create` oder `merged_update` geschrieben.

`Venue` ist dabei ein eigenes Domänenmodell. Der Merge arbeitet weiterhin mit Venue-Namen aus den Rohimporten, löst diese Namen beim Schreiben aber auf bestehende `venues` auf oder legt fehlende Venues automatisch neu an. Das Matching ist dabei bewusst flexibler als ein reiner Exaktvergleich: Varianten wie `Porsche Arena Stuttgart`, `Porsche-Arena` und `Porsche-Arena Stuttgart` werden als dieselbe Venue erkannt, während fachlich unterschiedliche Unterorte wie `Im Wizemann` und `Im Wizemann (Halle)` getrennt bleiben. Wenn sich der Venue-Name in späteren Rohdaten ändert, wird die Venue-Zuordnung des Events entsprechend auf die passende Venue umgehängt.

Im Backend gibt es für Venues einen eigenen Verwaltungsbereich unter `/backend/venues`. Die Liste startet dort bewusst leer und zeigt erst nach einer Suche Treffer an. Die Suche läuft bereits während des Tippens und aktualisiert die Trefferliste per Turbo, ohne dass die komplette Seite neu geladen werden muss. Gesucht wird nach Venue-Name, Adresse, Beschreibung und externer URL.

Auch die öffentliche Event-Suche versteht strukturierte Zeitphrasen wie `heute`, `morgen`, `diese Woche`, `dieses Wochenende` oder `am Wochenende`, kombiniert mit einer Venue wie `am Wochenende im Goldmark´s Stuttgart`. Wichtig dabei: Das Wochenende ist in dieser Suche bewusst als Freitag bis Sonntag definiert.

Zusätzlich zum exakten Dublettenschlüssel gibt es ein optionales Ähnlichkeits-Matching für Artist-Namen bei exakt gleicher Startzeit. Damit kann der Merge-Import auch Fälle wie `Vier Pianisten - Ein Konzert` und `Vier Pianisten` oder `Gregory Porter & Orchestra` und `Gregory Porter` als denselben Termin erkennen. Dieses Verhalten lässt sich im Backend unter `Einstellungen` über das Setting `Ähnlichkeits-Matching für Artist-Dubletten` ein- oder ausschalten.

Wichtig für das Verhalten im Backend:

- Neue oder aktualisierte automatisch gemergte Events werden nur dann direkt veröffentlicht, wenn die Pflichtfelder inklusive Bild vorhanden sind.
- Fehlen dafür wichtige Informationen, landet das Event stattdessen in `needs_review`.
- Erhält ein bestehendes `needs_review`-Event in einem späteren Merge nun alle Pflichtdaten, wird es automatisch nach `published` gehoben.
- Bereits automatisch veröffentlichte Events fallen ebenfalls zurück auf `needs_review`, wenn sie nach einem späteren Merge nicht mehr vollständig genug sind.
- Der Button zum Starten des Merge-Imports wird im Backend hervorgehoben, sobald seit dem letzten erfolgreichen Merge neue erfolgreiche Provider-Imports vorliegen.

Die Event-Status und ihre sichtbaren Labels sind dabei:

| Technischer Status | Sichtbares Label | Bedeutung |
| --- | --- | --- |
| `imported` | `importiert` | Interner Ausgangszustand des Modells. Im regulären redaktionellen Workflow spielt dieser Status normalerweise keine aktive Rolle mehr. |
| `needs_review` | `Draft` beziehungsweise `Drafts` in Filtern | Das Event ist noch nicht veröffentlichungsreif. Es fehlen Pflichtangaben, es braucht redaktionelle Prüfung oder beides. |
| `ready_for_publish` | `Unpublished` | Das Event ist fachlich vollständig, aber noch nicht veröffentlicht. |
| `published` | `Published` | Das Event ist veröffentlicht und öffentlich sichtbar, sobald `published_at` erreicht ist. Liegt `published_at` in der Zukunft, ist das Event bis dahin geplant, aber noch nicht öffentlich live. |
| `rejected` | `Rejected` | Das Event wurde bewusst verworfen und soll nicht veröffentlicht werden. |

Wichtig für Updates bestehender Events:

- Bei jedem Merge-Update werden `start_at`, `doors_at`, `venue`, `badge_text`, `min_price`, `max_price`, `primary_source`, `source_fingerprint` und `source_snapshot` neu aus den aktuellen Importdaten gesetzt.
- Das sichtbare Event-Feld `venue` verweist intern auf eine `Venue`. Im Editor gibt es dafür ein Search-as-you-type-Feld mit Vorschlägen aus den vorhandenen Venues; freie Eingaben legen beim Speichern bei Bedarf automatisch eine neue Venue an.
- `primary_source` bleibt bei bereits zusammengeführten Events auf der höchst priorisierten vorhandenen Quelle. Standardmäßig gilt dabei `easyticket` vor `eventim` vor `reservix`.
- `source_snapshot` wird quellenübergreifend zusammengeführt, statt bei späteren Merges nur noch den zuletzt verarbeiteten Provider zu enthalten.
- `event_offers` werden quellenweise auf den aktuellen Importstand synchronisiert: bestehende passende Offers werden aktualisiert, neue angelegt und nur Offers derselben gerade verarbeiteten Quelle entfernt, wenn sie dort nicht mehr vorkommen.
- Im Event-Editor kann die sichtbare Ticket-URL zusätzlich als manueller Override gespeichert werden. Dieser Override wird als eigenes `event_offer` mit `source = manual` angelegt oder aktualisiert und überschreibt keine importierten Offers direkt.
- Ein bloßes erneutes Speichern einer unveränderten importierten Ticket-URL erzeugt dabei bewusst kein zusätzliches manuelles Offer.
- Im Backend zeigt der Editor bei vorhandenem manuellem Override künftig diesen Wert an. Für die öffentliche Ticketlogik bleiben importierte Offers und deren Priorisierung weiterhin maßgeblich.
- Die öffentliche Ticketverfügbarkeit wird dabei nicht nur über `sold_out` abgeleitet, sondern zusätzlich über provider-spezifische Verfügbarkeits-Signale im Offer-Metadatum `availability_status`.
- Für `Eventim` gilt aktuell:
  - `eventStatus = 1` wird als `canceled` interpretiert und im Frontend als `Abgesagt` angezeigt.
  - Fehlt dieses Absage-Signal, aber es existiert keine `pricecategory` mehr mit `inventory = buchbar`, wird das Offer als `sold_out` behandelt und im Frontend als `Ausverkauft` angezeigt.
  - `Abgesagt` hat immer Vorrang vor `Ausverkauft`. Ein abgesagtes Event zeigt deshalb keinen Ticket-Link mehr, selbst wenn parallel noch manuelle Ticketdaten existieren.
  - Bei Events mit gepflegter `Ticket Sonderlocke` bleibt dieser Hinweis zusätzlich sichtbar, wenn das führende Status-Offer gleichzeitig `canceled` und `sold_out` signalisiert.
- Der führende öffentliche Status eines Events wird immer aus dem priorisierten öffentlichen Ticket-Status-Offer gelesen. Dadurch bleiben Fälle wie `Melrose Avenue = Ausverkauft` und `Juliano = Abgesagt` technisch sauber getrennt.
- Bilder werden ebenfalls quellenweise auf den aktuellen Merge-Stand synchronisiert.
- `title`, `artist_name`, `city`, `promoter_id`, `promoter_name`, `youtube_url`, `homepage_url`, `facebook_url` und `event_info` werden bei einem bestehenden Event durch den Merge nicht überschrieben. Diese Felder werden nur beim erstmaligen Anlegen aus den Importdaten vorbelegt.
- Manuelle redaktionelle Änderungen an genau diesen nicht überschriebenen Feldern bleiben bei späteren Merge-Läufen deshalb erhalten.
- Aktuell liefert nur `Reservix` einen lesbaren Veranstalternamen für `promoter_name`; `Eventim` und `Easyticket` liefern im aktuellen Rohdatenmodell weiterhin nur IDs.

Für die öffentliche Sichtbarkeit gilt zusätzlich:

- Gäste sehen ein `published`-Event erst ab `published_at`.
- Eingeloggte Redaktionsnutzer können die Event-Detailseite auch vor diesem Zeitpunkt öffnen, um geplante Veröffentlichungen zu prüfen.

Der Merge kann außerdem inkrementell auf Basis eines Zeitpunkts laufen. In diesem Fall werden nur Fingerprints neu gebaut, die seit `last_run_at` von neuen Rohimporten berührt wurden; für diese Gruppen wird aber jeweils wieder der aktuelle Gesamtstand aller Quellen zusammengeführt.

### Wie Social-Publishing für Events funktioniert

Das Backend unterstützt getrennte Drafts für Instagram und Facebook. Die Redaktion bearbeitet pro Event je Plattform einen eigenen Draft mit eigenem Status, eigenem Fehlerzustand und eigenem Publish-Versuch. Beim Öffnen des Social-Tabs legt die App fehlende Drafts automatisch an; neue Eventbilder erzeugen editierbare Social-Drafts neu, damit das aktuelle Eventbild verwendet wird.

Die Meta-Verbindungen werden dabei nicht über statische Einmal-Tokens in Credentials oder ENV gefahren, sondern über persistierte Onboarding- und Lifecycle-Flows im Backend-Tab `Einstellungen -> Meta Publishing`. Dort verbindet ein Admin Instagram und Facebook unabhängig voneinander. Details dazu stehen in [docs/META_ONBOARDING.md](docs/META_ONBOARDING.md).

Für den OAuth-Callback kann optional eine feste Redirect-URL über `meta.instagram_redirect_uri` bzw. `META_INSTAGRAM_REDIRECT_URI` gesetzt werden. Der Name ist historisch Instagram-spezifisch, die URL gilt aber für Instagram- und Facebook-Onboarding.

Sobald eine feste Redirect-URL gesetzt ist, muss der jeweilige Connect-Flow auch auf genau diesem Host gestartet werden. Der serverseitige OAuth-`state` hängt an der Session des Start-Hosts; ein lokal gestarteter Flow kann deshalb nicht sauber auf einer anderen Callback-Domain beendet werden.

Die Redaktion arbeitet dabei direkt im Event-Editor im Tab `Social`:

1. Beim Öffnen des Tabs existieren Instagram- und Facebook-Draft normalerweise bereits automatisch.
2. Ein Draft baut serverseitig eine Caption aus Eventdaten und wählt ein öffentlich erreichbares Bild.
3. Caption sowie die beiden Bildtext-Zeilen für Artist und Meta-Zeile können danach manuell angepasst werden.
4. Drafts können bei Bedarf manuell neu erzeugt werden; beim Hinzufügen oder Ändern des Eventbilds werden nicht veröffentlichte Drafts automatisch neu gebaut.
5. Die Veröffentlichung läuft direkt aus dem jeweiligen Plattform-Draft. Status, Fehler und externe IDs werden getrennt pro Plattform am jeweiligen `EventSocialPost` gespeichert.

Wichtig für die Generierung:

- Als Ziel-URL wird die kanonische öffentliche Event-URL verwendet.
- Als Bildquelle gilt zuerst das redaktionelle Eventbild, danach ein Promotion-Banner und danach ein Import-/Fallback-Bild.
- Der serverseitig gerenderte Bildtext folgt typografisch der `Unsere Highlights`-Kachel: `Bebas Neue` für den Artist und `Archivo Narrow` für Datum und Venue; der Event-Titel wird im Bild nicht separat gerendert.
- Die Caption enthält Artist oder Titel, Datum, Venue, einen kurzen Call-to-Action und die Event-URL.
- Damit das auf Production stabil funktioniert, werden die Runtime-Fonts zusätzlich im Docker-Image für Fontconfig/Pango installiert; die Browser-Webfonts bleiben davon unberührt.

Wichtig für die Veröffentlichung:

- Gesendet werden nur Events, die bereits öffentlich live sind. Ein geplantes `published_at` in der Zukunft reicht nicht.
- Instagram wird über den direkt verbundenen persistierten Instagram-Professional-Account per Media-Container und anschließendem `media_publish` veröffentlicht. Wenn eine Facebook-Seite verbunden ist, lädt die App das Social-Card-Bild vorher als unveröffentlichte Page-Photo hoch und verwendet die daraus entstehende Facebook-CDN-URL für den Instagram-Container. Das umgeht Fetch-Probleme der Instagram-API mit der eigenen App-Domain; es veröffentlicht keinen Facebook-Post.
- Facebook wird über die separat verbundene und ausgewählte Facebook-Seite direkt über die Facebook-Graph-API veröffentlicht.
- Ein Facebook-/Token-/Seitenfehler blockiert nur Facebook-Publishing. Für Instagram kann eine kaputte Facebook-Seitenverbindung zusätzlich den optionalen Bild-Relay verhindern; ohne Relay versucht Instagram weiterhin die direkte Bild-URL.
- Fehlgeschlagene Posts bleiben sichtbar und können nach einer Korrektur der Konfiguration erneut gesendet werden.

Wichtig für Betrieb und Architektur:

- Onboarding und Publishing sind strikt getrennt.
- Instagram und Facebook sind getrennte Meta-Verbindungen mit getrennten Tokens und Health Checks.
- Die Instagram-Graph-API-Payload für Bildposts bleibt ein normaler Image-Container mit `image_url`; `media_type` wird für reguläre Feed-Fotos nicht gesetzt.
- Token-Gültigkeit wird regelmäßig geprüft, serverseitige Refresh-Versuche laufen über einen wiederkehrenden Job, und `reauth_required` blockiert Publishing explizit statt implizit zu scheitern.

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
Zusätzlich ist standardmäßig ein täglicher automatischer Lauf um `05:05` Uhr (`Europe/Berlin`) konfiguriert.

Der Ablauf ist:

1. Zuerst wählt der Job geeignete bestehende Events aus, typischerweise solche ohne vollständige LLM-Anreicherung oder mit veralteten Enrichment-Daten.
2. Jedes Event wird einzeln verarbeitet; pro Event gibt es genau einen OpenAI-Call.
3. Vor diesem Call baut der Importer für `homepage_link`, `instagram_link`, `facebook_link` und `youtube_link` einen Suchkontext über den konfigurierten Web-Search-Provider auf.
4. Für jedes dieser vier Felder werden bis zu 10 Suchtreffer mit kontextreichen Feldern wie Titel, Snippet, angezeigtem Link, Quelle und zusätzlicher Ergebnisbeschreibung in den Prompt übernommen.
5. Das LLM liefert `genre`, `event_description`, `venue_description`, `venue_address`, `venue_external_url` sowie die vier Search-Linkfelder zurück. Nur die vier Search-Linkfelder dürfen aus den mitgelieferten Suchtreffern gewählt werden; `venue_external_url` kommt direkt aus Prompt und LLM-Response.
6. Anschließend wird geprüft, ob die zurückgegebenen Search-Links tatsächlich in den gelieferten Kandidatenlisten enthalten sind; `venue_external_url` wird technisch validiert.
7. Das Ergebnis wird normalisiert und als `event_llm_enrichments` am jeweiligen Event gespeichert.
8. Der Lauf protokolliert Auswahlmenge, übersprungene Events, erfolgreiche Enrichments, abgeschlossene OpenAI-Calls, Web-Search-Metriken und Fehler im zugehörigen `ImportRun`.

Fachlich ist wichtig:

- Das Enrichment arbeitet auf dem bestehenden Event-Bestand nach dem Merge.
- `event_description` bündelt die belastbaren Informationen zu Artist, Projekt/Produktion und konkretem Eventformat in einem einzigen zusammenhängenden Beschreibungstext.
- `EventLlmEnrichment.venue`, `venue_description`, `venue_external_url` und `venue_address` bleiben als Rohdaten erhalten.
- `homepage_link`, `instagram_link`, `facebook_link` und `youtube_link` werden vom LLM nur aus den gelieferten Top-10-Kandidaten des konfigurierten Search-Providers ausgewählt.
- `venue_external_url` wird direkt vom LLM aus Venue-Name und Event-Kontext ermittelt und anschließend technisch validiert.
- Die Search Provider `serpapi` und `openwebninja` bleiben austauschbar; beide liefern denselben normalisierten Suchkontext an den Prompt.
- Hat ein Event bereits eine zugeordnete `Venue`, ändert ein LLM-Lauf weder die Venue-Zuordnung noch `Venue.name`.
- Passt `EventLlmEnrichment.venue` zu der bereits zugeordneten `Venue`, dürfen `Venue.description`, `Venue.external_url` und `Venue.address` aus dem Enrichment nur dann ergänzt werden, wenn das jeweilige Venue-Feld noch leer ist. Bereits gepflegte Werte werden nicht überschrieben.
- Weicht `EventLlmEnrichment.venue` von der bereits zugeordneten `Venue` ab, bleibt die bestehende Venue vollständig unverändert.
- Hat ein Event noch keine zugeordnete `Venue`, darf aus `EventLlmEnrichment.venue` eine passende Venue gesucht oder neu angelegt und dem Event zugeordnet werden.
- In genau diesem Fallback-Fall dürfen zusätzlich `Venue.description`, `Venue.external_url` und `Venue.address` aus `EventLlmEnrichment.venue_description`, `venue_external_url` und `venue_address` gesetzt werden; auch hier werden bereits vorhandene Werte der gefundenen oder neu angelegten Venue nicht überschrieben.
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
- ein lokales Bildverarbeitungs-Backend für Active Storage, bevorzugt `libvips`, alternativ ImageMagick

Für die lokale Entwicklung und für den Produktionscontainer gilt dieselbe Ruby-Version. Kamal rollt die App als Docker-Image aus; der Produktionshost selbst braucht deshalb kein separates systemweites Ruby 4.

Wenn beim Laden von Bildvarianten Fehler wie `executable not found: "convert"` auftreten, fehlt lokal meist das ImageMagick-Kommandozeilenwerkzeug. In diesem Projekt ist `libvips` die bevorzugte Option; ohne `libvips` oder ImageMagick können verkleinerte Vorschaubilder und Web-Varianten nicht erzeugt werden.

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

### Locust / Lasttest

Für vorsichtige Read-only-Lasttests gibt es ein manuelles Locust-Skript unter `test/locust/locustfile.py`. Es ist bewusst nicht Teil von `bin/ci` und testet nur öffentliche `GET`-Seiten.

Lokal gegen die Entwicklungsumgebung:

```bash
bin/dev
locust -f test/locust/locustfile.py --host http://127.0.0.1:3000
```

Konservativer headless Smoke-Test lokal:

```bash
locust -f test/locust/locustfile.py \
  --host http://127.0.0.1:3000 \
  --headless \
  --users 2 \
  --spawn-rate 1 \
  --run-time 1m
```

Konservativer headless Smoke-Test gegen Production:

```bash
locust -f test/locust/locustfile.py \
  --host https://stuttgart-live.schopp3r.de \
  --headless \
  --users 3 \
  --spawn-rate 1 \
  --run-time 2m
```

Wichtig für den Ablauf:

- Der Host wird immer explizit über `--host` gesetzt und nicht im Skript fest verdrahtet.
- `on_start` entdeckt Event- und News-Detailseiten aus den öffentlichen HTML-Listen. Wenn keine Detailseiten gefunden werden, fällt der Test automatisch auf stabile Index-Seiten zurück.
- Für erste Production-Läufe nur kleine Nutzerzahlen, niedrige Spawn-Rate und kurze Laufzeiten verwenden. Keine aggressiven Ramp-ups ohne vorherige Abstimmung.
- Bei der Auswertung zuerst auf HTTP-Fehlerquote, p95/p99 sowie einzelne auffällige Request-Gruppen wie `GET /events/:slug` und `GET /news/:slug` schauen.

Für lokales oder staging-nahes Profiling von `/` und `/events` lassen sich zusätzlich opt-in Header aktivieren:

```bash
curl -sD - -o /dev/null \
  -H 'X-Stuttgart-Live-Profile: 1' \
  'http://127.0.0.1:3000/events?filter=all'
```

Die Antwort enthält dann `X-Stuttgart-Live-Profile` und `Server-Timing` mit Wall-Time, View-Zeit und SQL-Zeit. Das ist nur für gezielte Analyse gedacht und bewusst nicht standardmäßig aktiv.

## Wichtige Konfiguration

Nicht jede Variable wird in jeder Umgebung gebraucht. Für den Alltag sind diese Gruppen wichtig:

- `config/credentials.yml.enc`: `EASYTICKET_*`, `EVENTIM_USER`, `EVENTIM_PASS`, `EVENTIM_FEED_KEY`, `RESERVIX_API_KEY`, `RESERVIX_EVENTS_API`, `SERPAPI_API_KEY`, `openwebninja.api_key`, `MAILCHIMP_*`, `SMTP_*`, `sentry.dsn`, `meta.app_id`, `meta.app_secret`, optional `meta.instagram_app_id`, `meta.instagram_app_secret`, `meta.instagram_redirect_uri`
- statisch im Code: `GOOGLE_ANALYTICS_ID`, `MAILER_FROM`
- `config/deploy.hetzner.shared.yml`: `APP_HOST`, `KAMAL_WEB_HOST`, `KAMAL_SSH_HOST_KEY`
- lokale `.env`: `DB_PASSWORD`, `KAMAL_REGISTRY_PUSH_TOKEN`, `KAMAL_REGISTRY_PULL_PASSWORD`, optional `HCLOUD_TOKEN` für Hetzner-Terraform und optional `SENTRY_AUTH_TOKEN` für lokale Sentry-Release-Kommandos
- lokale Datei `config/master.key`: Schlüssel für `config/credentials.yml.enc`
- GitHub-Environment-Secrets für Deployments im Environment `production`: `DB_PASSWORD`, `RAILS_MASTER_KEY`, `KAMAL_REGISTRY_PULL_PASSWORD`, `KAMAL_SSH_PRIVATE_KEY`, `SENTRY_AUTH_TOKEN`
- GitHub-Repository-Secret für den Codex-Issue-Workflow: `OPENAI_API_KEY`
- GitHub-Variablen für Sentry-Releases: `SENTRY_ORG`, `SENTRY_PROJECT`

Ohne Mailchimp-Konfiguration funktioniert die lokale Speicherung von Newsletter-Anmeldungen weiterhin, nur der externe Sync bleibt aus.

### Credentials bearbeiten

Zum Hinzufügen oder Ändern von Einträgen in `config/credentials.yml.enc` öffnest du die Rails-Credentials mit dem im Projekt verwendeten Ruby über `mise`:

```bash
EDITOR="code --wait" mise exec -- bin/rails credentials:edit
```

Dann ergänzt du den gewünschten Schlüssel im YAML, zum Beispiel:

```yml
openai:
  api_key: sk-...
```

Für das Social-Publishing liegen nur die App-Zugangsdaten in den Rails-Credentials und nicht in `app_settings`. Facebook nutzt die Meta-App. Instagram kann eine eigene Instagram-Platform-App-ID benötigen; wenn keine eigenen Instagram-Werte gesetzt sind, fällt die App auf `meta.app_id` und `meta.app_secret` zurück:

```yml
meta:
  app_id: "..."
  app_secret: "..."
  instagram_app_id: "..."
  instagram_app_secret: "..."
  instagram_redirect_uri: "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback"
```

Nach dem Speichern und Schließen des Editors schreibt Rails die verschlüsselte Datei automatisch zurück. Voraussetzung ist eine vorhandene lokale `config/master.key`.

Zusätzlich gibt es Laufzeitkonfiguration in der Datenbank über `app_settings`. Diese Werte werden im Admin-Bereich unter `Einstellungen` gepflegt und sind bewusst nicht in Credentials oder Umgebungsvariablen abgelegt. Aktuell liegen dort unter anderem:

- `sks_promoter_ids` für SKS-Filter und Sortierung
- `sks_organizer_notes` für den Standardtext bei SKS-Events ohne eigene Veranstalterhinweise
- `llm_enrichment_model`, `llm_enrichment_prompt_template`, `llm_enrichment_temperature` und `llm_enrichment_web_search_provider` für den Enrichment-Job; projektseitig ist für `llm_enrichment_temperature` standardmäßig `1` gesetzt und entspricht damit dem OpenAI-API-Default. Niedrigere Werte liefern stabilere, höhere Werte variantenreichere Antworten. Standardmäßig bleibt `serpapi` für die Websuche aktiv; alternativ kann im Backend auf OpenWebNinja umgestellt werden, sofern `openwebninja.api_key` hinterlegt ist. Die Websuche wird für `homepage_link`, `instagram_link`, `facebook_link` und `youtube_link` gleichermaßen verwendet.
- `llm_genre_grouping_model`, `llm_genre_grouping_prompt_template` und `llm_genre_grouping_group_count` für den Genre-Gruppierungsjob
- `public_genre_grouping_snapshot_id` für den global öffentlich verwendeten Genre-Snapshot
- `merge_artist_similarity_matching_enabled` für das quellenübergreifende Ähnlichkeits-Matching von Artist-Namen im Merge-Import bei exakt gleicher Startzeit

### Meta-Setup für Social-Publishing

Damit Social-Posts aus dem Backend zuverlässig auf Instagram und Facebook funktionieren, muss das externe Meta-Setup zur hinterlegten App und den Ziel-Accounts passen:

- ein Instagram-Professional-Konto, also `Business` oder `Creator`
- eine konfigurierte Meta-App mit Instagram API with Instagram Login und Facebook Pages-Zugriff
- App-Domain `stuttgart-live.schopp3r.de`, Website-URL `https://stuttgart-live.schopp3r.de/` und erlaubte OAuth-Redirect-URL `https://stuttgart-live.schopp3r.de/backend/meta_connection/callback`
- Instagram-Scopes `instagram_business_basic` und `instagram_business_content_publish`
- Facebook-Scopes `pages_show_list`, `pages_read_engagement` und `pages_manage_posts`
- gültige App-Konfiguration für den serverseitigen OAuth- und Token-Refresh-Flow
- je ein im Backend erfolgreich durchlaufener Instagram- und Facebook-Connect-Flow
- eine ausgewählte Facebook-Seite, die vom verbindenden Facebook-Login verwaltet werden darf

Die Anwendung erwartet je eine globale Instagram- und Facebook-Verbindung. Es gibt also weiterhin keinen OAuth-Connect-Flow pro Redaktionsnutzer, aber Instagram und Facebook können unabhängig voneinander neu verbunden und geprüft werden.

Wenn ein Token rotiert oder die Berechtigungen ungültig werden, reicht es in der Regel, die Verbindung im Backend neu aufzubauen und anschließend einen Test-Post erneut zu senden.

Im Social-Tab prüft die App beide Meta-Verbindungen zusätzlich aktiv gegen die jeweiligen APIs. Dadurch werden abgelaufene oder falsch berechtigte Tokens schon vor dem Enqueue eines Publish-Jobs sichtbar. Direktes Facebook-Publishing ist nur aktiv, wenn in `Meta Publishing` genau eine Facebook-Seite ausgewählt ist.
Wenn keine gültige Verbindung mehr vorhanden ist, zeigt der Social-Tab direkt getrennte Buttons für `Instagram verbinden` und `Facebook verbinden`.

Beim Erzeugen eines Social-Drafts rendert die App zusätzlich ein eigenes Kartenbild im Highlight-Stil aus dem ausgewählten Eventbild:

- ein 4:5-Instagram-Bild (`publish_image_instagram`)

Die Redaktionsvorschau im Backend verwendet dasselbe 4:5-Instagram-Bild wie der Publish-Upload. Lange Artist-, Titel- und Venue-Texte werden serverseitig mit `...` gekürzt, damit das Layout nicht ausbricht.

### Typische Arbeitsweisen

Mit der aktuellen Struktur gibt es vier übliche Betriebsmodi:

- lokale Entwicklung: Rails liest App-Konfiguration aus `config/credentials.yml.enc`; dafür braucht die App vor allem `config/master.key`
- lokale Hetzner-Infrastruktur: Terraform nutzt lokal `HCLOUD_TOKEN`, typischerweise aus `.env` oder der Shell
- lokaler Produktions-Deploy: Kamal nutzt lokal `DB_PASSWORD` und `KAMAL_REGISTRY_PUSH_TOKEN` aus `.env` sowie `config/master.key`
- GitHub-Produktions-Deploy: GitHub Actions nutzt `DB_PASSWORD`, `RAILS_MASTER_KEY`, `KAMAL_REGISTRY_PULL_PASSWORD` und `KAMAL_SSH_PRIVATE_KEY` aus GitHub-Secrets; für den Build-Push nach GHCR verwendet der Workflow das temporäre `github.token`

Für Sentry gilt zusätzlich:

- die Laufzeit-App liest die `dsn` aus `config/credentials.yml.enc`
- der Produktions-Container bekommt `SENTRY_ENVIRONMENT=production`
- der Produktions-Deploy setzt `SENTRY_RELEASE` automatisch auf die deployte Git-SHA
- nach erfolgreichem GitHub-Deploy meldet der Workflow denselben Release per `sentry-cli` an Sentry und verknüpft automatisch die Commits

Wenn du lokal sowohl entwickelst als auch Hetzner-Infrastruktur steuerst und manuell nach Produktion deployen willst, reicht aktuell in `.env` in der Regel:

```dotenv
DB_PASSWORD=...
HCLOUD_TOKEN=...
KAMAL_REGISTRY_PUSH_TOKEN=...
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

Zusätzlich gibt es einen GitHub-Actions-Workflow für kleine automatisierte Bugfixes aus Issues: Wenn ein GitHub-Issue das Label `codex-fix` erhält, rendert der Workflow aus Titel und Beschreibung einen Codex-Prompt, lässt Codex den kleinstmöglichen Fix im Repository umsetzen, führt danach `bin/ci` aus und eröffnet nur bei erfolgreicher Verifikation automatisch einen Pull Request gegen den Default-Branch. Die PR-Beschreibung verlinkt das auslösende Issue und übernimmt Codex' abschließende Erklärung zu Problem und Lösung. Dafür müssen im Repository das Secret `OPENAI_API_KEY` sowie die GitHub-Einstellung zum Erstellen von Pull Requests durch Actions aktiviert sein.

Bestehende Codex-PRs lassen sich danach per Kommentar nachschärfen: Ein neuer PR-Kommentar oder Inline-Review-Kommentar, der mit `/codex fix` oder `/codex address` beginnt, startet einen zweiten Workflow auf dem bestehenden PR-Branch. Der Workflow übernimmt PR-Titel, PR-Body und den auslösenden Kommentar als Prompt, lädt zusätzlich GitHub-hosted Screenshots aus PR-Body und Kommentar vor dem Codex-Lauf lokal herunter, führt erneut `bin/ci` aus und pusht nur bei erfolgreicher Verifikation zurück in denselben PR. Aus Sicherheitsgründen reagieren diese Slash-Kommandos nur auf Kommentare von `OWNER`, `MEMBER` oder `COLLABORATOR`, nur bei PRs aus demselben Repository und nur auf Screenshots von GitHub-eigenen Hosts.

Der Issue-Workflow für `codex-fix` lädt GitHub-hosted Screenshots aus dem Issue-Body auf dieselbe Weise lokal herunter und gibt sie Codex zusätzlich als Bild-Inputs mit. Reine externe Bild-Links außerhalb der von GitHub gehosteten Asset-Domains werden bewusst ignoriert.

Das Skript `script/github_set_production_secrets` setzt dafür sowohl die benötigten Production-Environment-Secrets als auch das Repository-Secret `OPENAI_API_KEY` aus der lokalen `.env`.

Webprozess und Job-Verarbeitung laufen in Production getrennt. Kamal startet eine `web`-Rolle für den öffentlichen Traffic und zusätzlich eine `job`-Rolle mit `bin/jobs`, damit Queue-Arbeit nicht mehr im selben Puma-Prozess um dieselben Threads konkurriert.
Für den Einzelhost ist der Webprozess bewusst konservativ auf `WEB_CONCURRENCY=2` und `RAILS_MAX_THREADS=3` gesetzt. Die Datenbank-Pools werden zusätzlich explizit über `DB_POOL` und `QUEUE_DB_POOL` festgelegt.
Öffentliche Active-Storage-Bilder laufen in Production nicht mehr über Rails-Streaming: Rails erzeugt signierte `/media/...`-URLs, `nginx` im App-Container validiert diese URLs und liefert die Dateien direkt aus `/rails/storage` aus. Lokale Entwicklung und Tests bleiben beim Rails-Proxy für Active Storage.

Die produktive öffentliche Domain, die Ziel-IP und der gepinnte SSH-Host-Key stehen versioniert in [config/deploy.hetzner.shared.yml](/Users/marc/Projects/stuttgart-live.de/config/deploy.hetzner.shared.yml).
Die Datei bleibt bewusst außerhalb des Docker-Build-Kontexts; Kamal setzt `APP_HOST` daraus zur Laufzeit in den Produktions-Container.

### Was lokal wichtig ist

Für manuelle Produktions-Kommandos brauchst du lokal:

- `config/master.key`
- die versionierte Datei `config/deploy.hetzner.shared.yml`
- eine lokale `.kamal/secrets.hetzner`
- den SSH-Key `~/.ssh/stgt-live-hetzner-github` für den Benutzer `deploy`
- optional den SSH-Key `~/.ssh/stgt-live-hetzner-admin` für Host-Administration als `admin`
- eine `.env` mit `DB_PASSWORD`, `KAMAL_REGISTRY_PUSH_TOKEN` und `KAMAL_REGISTRY_PULL_PASSWORD`
- eine `.env` mit `MEDIA_PROXY_SECRET`, wenn du das Produktions-Setup lokal gegen Hetzner prüfst oder deployen willst

Für lokale Sentry-Release-Meldungen zusätzlich:

- `SENTRY_AUTH_TOKEN` in `.env` oder in der Shell
- optional `SENTRY_ORG` und `SENTRY_PROJECT`; Default im Repo ist aktuell `self-employed-gi` und `stuttgart-live`

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
- `MEDIA_PROXY_SECRET`
- `RAILS_MASTER_KEY`
- `KAMAL_REGISTRY_PULL_PASSWORD`
- `KAMAL_SSH_PRIVATE_KEY`
- `SENTRY_AUTH_TOKEN`

Zusätzlich werden diese GitHub-Variablen verwendet:

- `SENTRY_ORG`
- `SENTRY_PROJECT`

Nicht-geheime Zielwerte für Domain, Server-IP und gepinnten SSH-Host-Key werden nicht mehr als GitHub-Variablen gepflegt.

### Die wichtigsten Kommandos

Deployment von lokal:

```bash
bin/hetzner-check
bin/kamal deploy -d hetzner
bin/sentry-release
bin/hetzner-check
bin/kamal redeploy -d hetzner
bin/sentry-release
bin/hetzner-check
bin/kamal rollback <VERSION> -d hetzner
```

`bin/sentry-release` meldet den aktuellen Git-Commit als Release an Sentry, verknüpft automatisch die Commits, finalisiert den Release und markiert einen Deploy für `production`.

Status und Logs:

```bash
bin/kamal details -d hetzner
bin/kamal proxy reboot -d hetzner
bin/kamal app containers -d hetzner
bin/kamal app version -d hetzner
bin/kamal app logs -f -d hetzner -r web
bin/kamal app logs -f -d hetzner -r job
bin/kamal app logs --since 15m -d hetzner -r web
bin/kamal app logs --since 30m --grep ERROR -d hetzner -r job
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
Öffentliche Bild-URLs zeigen in Production auf signierte `/media/...`-Pfade. Wenn ein Bild im Backend ersetzt oder eine Variant/Crop-Änderung gespeichert wird, rendert Rails eine neue URL. Damit wird kein manuelles Cache-Purging für den Media-Pfad benötigt.

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

Bestehende Venue-Dubletten anhand des flexiblen Venue-Matchings zusammenführen:

```bash
mise exec -- bin/rails venues:maintenance:backfill_duplicates
```

Der Task gruppiert bestehende Venues über denselben Match-Key wie der Merge-Import, hängt Events auf eine kanonische Venue um, übernimmt fehlende Metadaten und ein vorhandenes Logo und löscht anschließend redundante Dubletten wie `LKA-Longhorn Stuttgart` neben `LKA-Longhorn`.

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
