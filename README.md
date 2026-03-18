# stuttgart-live.de

`stuttgart-live.de` ist ein lokales Stadtmagazin für Veranstaltungen, Kultur und Freizeittipps in Stuttgart. Die Anwendung sammelt Termine aus verschiedenen Quellen, führt sie redaktionell zusammen und veröffentlicht sie in einer schnellen, klaren Oberfläche.

Das Repository enthält die komplette Anwendung: öffentliche Website, redaktionelles Backend, Importlogik, Hintergrundjobs und die wichtigsten Deploy- und Betriebsbausteine.

## Kurzüberblick

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

Wichtig für das Verhalten im Backend:

- Neue oder aktualisierte automatisch gemergte Events werden nur dann direkt veröffentlicht, wenn die Pflichtfelder inklusive Bild vorhanden sind.
- Fehlen dafür wichtige Informationen, landet das Event stattdessen in `needs_review`.
- Bereits automatisch veröffentlichte Events fallen ebenfalls zurück auf `needs_review`, wenn sie nach einem späteren Merge nicht mehr vollständig genug sind.
- Der Button zum Starten des Merge-Imports wird im Backend hervorgehoben, sobald seit dem letzten erfolgreichen Merge neue erfolgreiche Provider-Imports vorliegen.

Wichtig für Updates bestehender Events:

- Bei jedem Merge-Update werden `start_at`, `doors_at`, `venue`, `badge_text`, `min_price`, `max_price`, `primary_source`, `source_fingerprint` und `source_snapshot` neu aus den aktuellen Importdaten gesetzt.
- `event_offers` werden vollständig auf den aktuellen Importstand synchronisiert: bestehende passende Offers werden aktualisiert, neue angelegt und nicht mehr vorhandene entfernt.
- Bilder werden ebenfalls auf den aktuellen Merge-Stand synchronisiert.
- `title`, `artist_name`, `city`, `promoter_id`, `youtube_url`, `homepage_url`, `facebook_url` und `event_info` werden bei einem bestehenden Event durch den Merge nicht überschrieben. Diese Felder werden nur beim erstmaligen Anlegen aus den Importdaten vorbelegt.
- Manuelle redaktionelle Änderungen an genau diesen nicht überschriebenen Feldern bleiben bei späteren Merge-Läufen deshalb erhalten.

Der Merge kann außerdem inkrementell auf Basis eines Zeitpunkts laufen. In diesem Fall werden nur Fingerprints neu gebaut, die seit `last_run_at` von neuen Rohimporten berührt wurden; für diese Gruppen wird aber jeweils wieder der aktuelle Gesamtstand aller Quellen zusammengeführt.

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

- Ruby in der Projektversion
- PostgreSQL
- Node.js und npm

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

Zusätzlich gibt es Laufzeitkonfiguration in der Datenbank über `app_settings`. Diese Werte werden im Admin-Bereich unter `Einstellungen` gepflegt und sind bewusst nicht in Credentials oder Umgebungsvariablen abgelegt. Aktuell liegen dort unter anderem die `sks_promoter_ids` für SKS-Filter und Sortierung sowie die `sks_organizer_notes` für den Standardtext bei SKS-Events ohne eigene Veranstalterhinweise.

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
bin/kamal app containers -d hetzner
bin/kamal app version -d hetzner
bin/kamal app logs -f -d hetzner
bin/kamal app logs --since 15m -d hetzner
bin/kamal app logs --since 30m --grep ERROR -d hetzner
```

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
