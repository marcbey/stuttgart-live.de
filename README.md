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
- `ImportSource`, `ImportRun` und anbieterspezifische Importmodelle für Rohdaten und Laufprotokolle
- `BlogPost` für redaktionelle Inhalte
- `NewsletterSubscriber` für Newsletter-Anmeldungen

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

- `DB_*` und `RAILS_MASTER_KEY` für Anwendung und Deployment
- `EASYTICKET_*`, `EVENTIM_*`, `RESERVIX_*` für externe Event-Importe
- `MAILCHIMP_API_KEY`, `MAILCHIMP_LIST_ID`, `MAILCHIMP_SERVER_PREFIX` für den optionalen Newsletter-Sync
- `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, optional `SMTP_DOMAIN`, `SMTP_AUTHENTICATION`, `SMTP_ENABLE_STARTTLS_AUTO` sowie `MAILER_FROM` für produktiven Mailversand
- `GOOGLE_ANALYTICS_ID` für GA4 nach Einwilligung im Consent-Banner

Ohne Mailchimp-Konfiguration funktioniert die lokale Speicherung von Newsletter-Anmeldungen weiterhin, nur der externe Sync bleibt aus.

## Qualitätssicherung

Der Standardweg für Prüfungen ist:

```bash
bin/ci
```

`bin/ci` bündelt Setup, Linting, Security-Checks und Tests. Vor einem Push sollte dieser Lauf grün sein.

## Deployment und Betrieb

Produktion läuft auf Hetzner und wird mit Kamal ausgerollt. Im Alltag gibt es zwei Wege:

- automatische Deployments über GitHub Actions nach Pushes auf `main`
- manuelle Eingriffe von lokal per `bin/kamal ... -d hetzner`

Webprozess und Job-Verarbeitung laufen gemeinsam in der Rails-Anwendung. `SOLID_QUEUE_IN_PUMA=true` ist für dieses Setup bereits vorgesehen.

### Was lokal wichtig ist

Für manuelle Produktions-Kommandos brauchst du lokal:

- `config/master.key`
- eine lokale `.kamal/secrets.hetzner`
- den SSH-Key `~/.ssh/stgt-live-hetzner-github` für den Benutzer `deploy`
- optional den SSH-Key `~/.ssh/stgt-live-hetzner-admin` für Host-Administration als `admin`

Der Standard-Host ist aktuell `46.225.224.194`. Falls sich die Ziel-IP ändert, kann sie über `KAMAL_WEB_HOST` überschrieben werden.

Wichtig: Die lokale `.kamal/secrets.hetzner` ist hier keine Klartext-Secret-Datei. Sie ist ignoriert und löst Werte aus `.env` und `config/master.key` auf. Als Vorlage dient `.kamal/secrets.hetzner.example`.

GitHub Actions nutzt diese lokale Datei nicht. Der Workflow erzeugt zur Laufzeit eine eigene `.kamal/secrets.hetzner` aus den in GitHub hinterlegten Secrets.

### Die wichtigsten Kommandos

Deployment von lokal:

```bash
bin/kamal deploy -d hetzner
bin/kamal redeploy -d hetzner
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
bin/kamal app exec --interactive --reuse "bin/rails console" -d hetzner
bin/kamal app exec --interactive --reuse "bash" -d hetzner
bin/kamal app exec --reuse "bin/rake <namespace>:<task>" -d hetzner
bin/kamal app exec --reuse "bin/rails runner 'puts Event.count'" -d hetzner
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

### Wenn es Probleme gibt

Für die meisten Störungen reicht diese Reihenfolge:

1. `bin/kamal details -d hetzner` prüfen
2. `bin/kamal app logs --since 15m -d hetzner` ansehen
3. bei App-Fehlern per `bin/kamal app exec --interactive --reuse "bin/rails console" -d hetzner` in die Konsole
4. bei Host-Problemen per SSH `docker ps` und `systemctl status docker` prüfen
5. bei einem kaputten Release gezielt `bin/kamal rollback <VERSION> -d hetzner` ausführen

## Weiterführende Dateien

Wenn du tiefer einsteigen willst, sind diese Dateien meist die besten Startpunkte:

- `config/routes.rb` für die fachliche Struktur der HTTP-Oberfläche
- `app/services` für zentrale Geschäftslogik
- `app/queries` für Listen- und Lesezugriffe
- `app/jobs` für Hintergrundverarbeitung
- `config/ci.rb` für den CI-Ablauf
- `config/deploy.hetzner.yml` für das Produktions-Deployment
- `HETZNER.md`, `INFRA.md` und `infra/ansible/README.md` für Infrastrukturdetails
