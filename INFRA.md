# Infra Plan: Hetzner + Terraform + Ansible + GitHub Deploy

Stand: 10. März 2026

## Ziel

Die Infrastruktur für `stuttgart-live.de` soll auf Hetzner reproduzierbar aufgebaut werden, damit sie später auch in einem anderen Hetzner-Konto mit möglichst wenig manueller Arbeit neu erstellt werden kann.

Die Betriebsverantwortung wird klar getrennt:

- `Terraform` provisioniert Hetzner-Ressourcen
- `Ansible` konfiguriert den Server
- `Kamal` deployt die Rails-App
- `GitHub Actions` fuehrt nur CI und App-Deploy aus

Nicht Teil von GitHub Actions:

- `terraform apply`
- `ansible-playbook`
- Host-Administration
- manuelle Recovery-Schritte

## Ausgangslage im Repo

Der produktive Infrastrukturpfad liegt jetzt vollständig auf Hetzner:

- Hetzner-Terraform unter [infra/terraform/hetzner](/Users/marc/Projects/stuttgart-live.de/infra/terraform/hetzner)
- GitHub-Environment-Verwaltung unter [infra/terraform/github](/Users/marc/Projects/stuttgart-live.de/infra/terraform/github)
- Hetzner-Deploy-Datei unter [config/deploy.hetzner.yml](/Users/marc/Projects/stuttgart-live.de/config/deploy.hetzner.yml)
- vorhandene CI in [ci.yml](/Users/marc/Projects/stuttgart-live.de/.github/workflows/ci.yml)

## Zielarchitektur

Die Zielarchitektur für V1 ist bewusst einfach:

- 1x Hetzner Cloud Server `CX33`
- `Ubuntu 24.04`
- `Primary IPv4` aktiviert
- `IPv6` optional zusätzlich aktiviert
- `Docker` auf dem Host
- `PostgreSQL` lokal auf dem Host
- `Kamal` für App-Deploys
- `kamal-proxy` fuer TLS und Routing
- lokale Uploads über persistentes Volume für `/rails/storage`
- Hetzner Server Backups aktiviert

Diese Architektur passt zum aktuellen Rails-Setup:

- Production-Datenbanken liegen bereits auf `127.0.0.1` als Default: [config/database.yml](/Users/marc/Projects/stuttgart-live.de/config/database.yml)
- Solid Queue kann im Puma-Prozess laufen: [config/puma.rb](/Users/marc/Projects/stuttgart-live.de/config/puma.rb)

## Architekturprinzipien

- Ein einziger Produktionsserver ist für V1 akzeptabel.
- Wiederholbarkeit ist wichtiger als maximale Plattform-Komplexität.
- Infrastruktur-Code darf keine App-Secrets im State speichern.
- Host-Konfiguration gehört in Ansible, nicht in fragile Einmal-Skripte.
- GitHub deployt nur die Anwendung auf einen bereits vorbereiteten Host.

## Verantwortlichkeiten

### Terraform

Terraform verwaltet ausschließlich Hetzner-Ressourcen:

- Projekt-/Namenskonventionen
- SSH-Key-Registrierung bei Hetzner
- Server `CX33`
- Primary IPv4
- optionale IPv6-Aktivierung
- Hetzner Backups
- Firewall
- optional Volume
- optionale Reverse-DNS-Einträge

Terraform verwaltet nicht:

- Docker-Installation
- PostgreSQL-Setup
- UFW/Fail2ban-Konfiguration auf dem Host
- App-Secrets

### Ansible

Ansible konfiguriert den laufenden Server:

- Benutzer und SSH-Hardening
- Zeitzone und Basis-Pakete
- Docker Engine
- PostgreSQL
- Datenbank-User und Datenbanken
- UFW und Fail2ban
- Backup-Skripte und Cronjobs
- optionale Monitoring-Agenten

### Kamal

Kamal übernimmt nur den App-Lifecycle:

- Container deployen
- neue Versionen aktivieren
- `kamal-proxy`
- Rollbacks
- Volumes für `/rails/storage`

### GitHub Actions

GitHub Actions übernimmt:

- Tests
- Build des App-Images
- Push in die Registry
- `kamal deploy` auf Hetzner
- optional verwaltet Terraform das GitHub-Environment `production`

GitHub Actions übernimmt nicht:

- Infrastruktur-Provisionierung
- Server-Hardening
- Datenbank-Administration auf Host-Ebene

## Zielstruktur im Repo

Die Repo-Struktur für den aktuellen Produktionspfad sieht so aus:

```text
infra/
  terraform/
    github/
      environments/
        production/
    hetzner/
      environments/
        prod/
      modules/
        app_server/
        firewall/
        ssh_key/
  ansible/
    inventories/
      production/
        hosts.yml
        group_vars/
    playbooks/
      bootstrap.yml
      app_host.yml
    roles/
      base/
      docker/
      postgres/
      firewall/
      backups/
.github/
  workflows/
    ci.yml
    deploy-production.yml
config/
  deploy.hetzner.yml
.kamal/
  secrets.hetzner.example
```

Hinweis:

- GitHub-Environment-Secrets und Variables können zusätzlich unter [infra/terraform/github](/Users/marc/Projects/stuttgart-live.de/infra/terraform/github) verwaltet werden.
- Der Hetzner-Stack lebt in einem eigenen Pfad, damit Provisionierung und Host-Konfiguration klar getrennt bleiben.

## Terraform-Plan für Hetzner

### Ziel

Terraform soll einen neuen Host in einem beliebigen Hetzner-Konto mit denselben Parametern reproduzierbar anlegen können.

### Ressourcen fuer V1

- `hcloud_ssh_key`
- `hcloud_server`
- `hcloud_firewall`
- Firewall-Attachments
- optional `hcloud_volume`
- optional `hcloud_rdns`

### Minimale Variablen

- `hcloud_token`
- `project`
- `environment`
- `server_name`
- `server_type` mit Default `cx33`
- `location` oder `datacenter`
- `image` mit Default `ubuntu-24.04`
- `enable_ipv4` mit Default `true`
- `enable_ipv6` mit Default `true`
- `enable_backups` mit Default `true`
- `ssh_key_name`
- `ssh_public_key`
- `allowed_ssh_cidrs`
- `app_domain`

### Terraform-Outputs

Diese Outputs müssen für Ansible und Kamal leicht nutzbar sein:

- `server_name`
- `server_ipv4`
- `server_ipv6`
- `ssh_user`
- `app_domain`

### Remote State

Da die Infrastruktur später in einem anderen Hetzner-Konto neu aufgebaut werden können soll, sollte der Terraform-State nicht auf dem Zielserver liegen.

Empfehlung:

- Terraform Cloud als einfachste Lösung
- alternativ ein S3-kompatibles Backend außerhalb des Zielkontos

Nicht empfohlen:

- lokaler State auf Entwicklerrechnern als dauerhaftes Betriebsmodell
- State-Ablage auf dem zu provisionierenden Produktionsserver

## Ansible-Plan

### Ziel

Ansible soll aus einem frisch provisionierten Ubuntu-Host einen Kamal-fähigen Produktionsserver machen.

### Reihenfolge der Playbooks

1. `bootstrap.yml`
2. `app_host.yml`

### Inhalt von `bootstrap.yml`

- Zeitzone auf `Europe/Berlin`
- Paketquellen aktualisieren
- Basis-Pakete installieren
- Deploy-User anlegen
- SSH-Hardening
- optional Root-Login deaktivieren
- UFW aktivieren
- Fail2ban aktivieren

### Inhalt von `app_host.yml`

- Docker installieren und starten
- Docker-Gruppe und Benutzerrechte setzen
- PostgreSQL installieren
- DB-Rolle `stuttgart_live_de` anlegen
- Datenbanken anlegen:
  - `stuttgart_live_de_production`
  - `stuttgart_live_de_production_cache`
  - `stuttgart_live_de_production_queue`
  - `stuttgart_live_de_production_cable`
- Backup-Skripte für `pg_dump` installieren
- Cronjob für tägliche Dumps einrichten
- optional Sicherung von `/rails/storage`

### Ansible-Inventar

Das Inventar für Production sollte nicht auf Handarbeit beruhen.

Empfehlung:

- Terraform-Outputs in ein statisches Inventory rendern
- oder ein kleines Skript, das aus Terraform-Outputs ein Ansible-Inventar erzeugt

Ziel:

- kein manuelles Eintragen der Server-IP vor jedem Lauf

## App- und Kamal-Anpassungen

Damit die App zur Hetzner-Architektur passt, sind folgende Anpassungen einzuplanen:

### Neue Deploy-Datei

Neue Datei:

- [config/deploy.hetzner.yml](/Users/marc/Projects/stuttgart-live.de/config/deploy.hetzner.yml)

Inhaltlich:

- `servers.web` mit Hetzner-Host
- `proxy.ssl: true`
- `proxy.host` mit Produktionsdomain
- Registry auf `ghcr.io`
- `SOLID_QUEUE_IN_PUMA=true`
- `DB_HOST=127.0.0.1`
- `DB_PORT=5432`
- `DB_NAME=stuttgart_live_de_production`
- `DB_USER=stuttgart_live_de`
- Volume für `/rails/storage`
- SSH-User passend zu Ansible-Setup

### Neue Secret-Beispieldatei

Neue Datei:

- `.kamal/secrets.hetzner.example`

Enthält mindestens:

- `RAILS_MASTER_KEY`
- `DB_PASSWORD`
- Drittanbieter-API-Secrets
- optional Registry-Token, falls nötig

### Rails-Produktionskonfiguration

Die Hetzner-Zielarchitektur verwendet lokale Uploads statt S3. Deshalb muss die Production-Konfiguration angepasst werden.

Bereits umgesetzt:

- Active Storage ist in Production env-gesteuert
- Default für Hetzner ist `:local`

Für `kamal-proxy` zusätzlich aktivieren:

- `config.assume_ssl = true`
- `config.force_ssl = true`

## GitHub Actions für Deploys

### Ziel

GitHub soll nur die Anwendung deployen, nicht die Infrastruktur provisionieren.

### Workflow `deploy-production.yml`

Trigger:

- Push auf `main`
- optional `workflow_dispatch`

Schritte:

1. Checkout
2. Ruby und Docker Buildx einrichten
3. optional Tests oder Abhängigkeit auf erfolgreiche CI
4. Docker-Login bei `ghcr.io`
5. SSH-Key aus GitHub Secret schreiben
6. bekannte Hosts vorbereiten
7. Kamal-Umgebungsvariablen setzen
8. `bin/kamal deploy -d hetzner --skip_push`

### GitHub Secrets / Environment Secrets

Im GitHub-Environment `production`:

- `KAMAL_WEB_HOST`
- `KAMAL_SSH_PRIVATE_KEY`
- `KAMAL_SSH_HOST_KEY`
- `APP_HOST`
- `KAMAL_REGISTRY_PULL_PASSWORD`
- `RAILS_MASTER_KEY`
- `DB_PASSWORD`
- API-Secrets für Drittanbieter

## Lokale Deploys und Admin-Kommandos

### Ziel

Von einem lokalen Admin-Rechner aus sollen Host-Konfiguration, Diagnose und
gezielte Redeploys möglich sein, ohne den GitHub-Workflow zu ersetzen.

### Voraussetzungen lokal

- `.env` mit allen App-Secrets
- `config/master.key`
- `~/.ssh/stgt-live-hetzner-admin` für Ansible und Admin-Zugriff
- `~/.ssh/stgt-live-hetzner-github` für Kamal-Deploys
- `KAMAL_REGISTRY_PULL_PASSWORD` in `.env`

### Host lokal konfigurieren

Für Docker, PostgreSQL, Firewall und Backups:

```bash
script/ansible_app_host_production
```

Das Skript liest `DB_PASSWORD` direkt aus `.env` und ruft `app_host.yml`
mit dem gehärteten `admin`-Benutzer auf.

### Kamal lokal verwenden

Für Diagnose und Admin-Zugriff:

```bash
bin/kamal logs -d hetzner
bin/kamal console -d hetzner
bin/kamal shell -d hetzner
bin/kamal app exec -d hetzner "bin/rails db:prepare"
```

### Lokaler Redeploy eines vorhandenen Images

Wenn das Ziel-Image bereits in `ghcr.io` existiert, kann es lokal erneut
ausgerollt werden:

```bash
bin/kamal deploy -d hetzner --skip_push
```

Wichtig:

- Das funktioniert nur für Images, die bereits in `ghcr.io` vorhanden sind.
- Bei uncommitteten lokalen Änderungen erwartet Kamal einen lokalen
  `_uncommitted_...`-Tag, der in der Registry normalerweise nicht existiert.

### Was lokal bewusst nicht der Standardpfad ist

Ein vollständiger lokaler `build + push + deploy` ist im aktuellen Setup nicht
der Standard, weil:

- GitHub den Build-Push mit `github.token` übernimmt
- der lokale Registry-Token bewusst nur Pull-Rechte hat

Für den normalen Produktionspfad ist deshalb vorgesehen:

- Push auf `main`
- GitHub baut das Image
- GitHub pusht nach `ghcr.io`
- GitHub deployt per Kamal auf Hetzner

### Registry-Strategie

Empfehlung:

- `ghcr.io`

Gründe:

- passt natürlich zu GitHub Actions
- keine zusätzliche Registry-Infrastruktur im Projekt
- einfacher Build-und-Push-Ablauf

### GitHub-Schutzmechanismen

Empfohlen für das Environment `production`:

- Required reviewers
- geschützte Branches
- Deploy nur von `main`
- klare Trennung von `CI` und `Deploy`

## Migrationsplan in Phasen

### Phase 1: Architektur festziehen

Ergebnis:

- Zielarchitektur beschlossen
- Hetzner als einziger Produktionspfad
- klare Trennung zwischen Infra und App-Deploy

Arbeitspakete:

- Hetzner-Ressourcenliste finalisieren
- Registry-Entscheidung auf `ghcr.io`
- Namensschema für Server, Firewall und Volumes festlegen

### Phase 2: Terraform für Hetzner aufsetzen

Ergebnis:

- neuer Hetzner-Terraform-Stack vorhanden

Arbeitspakete:

- `infra/terraform/hetzner` anlegen
- Provider und Module aufsetzen
- Variablen und Outputs definieren
- State-Backend festlegen
- `terraform.tfvars.example` schreiben

Abnahmekriterium:

- neuer Server kann in leerem Hetzner-Konto per `terraform apply` erstellt werden

### Phase 3: Ansible für Host-Konfiguration aufsetzen

Ergebnis:

- frisch provisionierter Host wird deterministisch konfiguriert

Arbeitspakete:

- Inventarstruktur anlegen
- Rollen für `base`, `docker`, `postgres`, `firewall`, `backups` erstellen
- DB-Rollen und Datenbanken automatisieren
- Cronjobs fuer Backups anlegen

Abnahmekriterium:

- ein nackter Ubuntu-Host ist nach `ansible-playbook` deploybereit

### Phase 4: Kamal auf Hetzner umstellen

Ergebnis:

- separater Hetzner-Deploypfad vorhanden

Arbeitspakete:

- `config/deploy.hetzner.yml` anlegen
- `.kamal/secrets.hetzner.example` anlegen
- Production-Konfiguration für lokalen Storage vorbereiten
- SSL-Settings aktivieren

Abnahmekriterium:

- `bin/kamal setup -c config/deploy.hetzner.yml` funktioniert gegen den neuen Host

### Phase 5: GitHub Deploy-Workflow aufsetzen

Ergebnis:

- App-Deploy läuft automatisiert über GitHub

Arbeitspakete:

- `deploy-production.yml` anlegen
- GitHub Environment `production` konfigurieren
- GHCR-Login und SSH-Key-Handling einbauen
- Kamal-Deploy aus GitHub testen

Abnahmekriterium:

- Merge nach `main` kann erfolgreich auf Hetzner deployen

### Phase 6: Produktivschaltung

Ergebnis:

- Hetzner wird produktiver Deploy-Zielpfad

Arbeitspakete:

- DNS auf Hetzner-IP zeigen lassen
- HTTPS testen
- `/up` Healthcheck testen
- Uploads testen
- Job-Ausführung über Solid Queue testen
- Restore-Test für DB-Backup durchführen

Abnahmekriterium:

- App ist über Produktionsdomain erreichbar und Wiederherstellung wurde getestet

## Betriebs- und Recovery-Plan

### Regelmäßige Betriebsaufgaben

- Hetzner-Backups überwachen
- tägliche `pg_dump`-Backups prüfen
- freien Plattenplatz prüfen
- Docker-Image- und Container-Cleanup
- regelmäßige Paket-Updates über Ansible

### Recovery-Ziele

Im Desasterfall muss Folgendes reproduzierbar möglich sein:

1. neuen Server per Terraform erzeugen
2. Server per Ansible konfigurieren
3. Datenbank aus Backup wiederherstellen
4. `/rails/storage` aus Sicherung zurückspielen
5. App per GitHub/Kamal erneut deployen
6. DNS auf neue IP umstellen, falls nötig

## Offene Entscheidungen

Diese Punkte müssen vor der Umsetzung final festgelegt werden:

- Terraform-State in Terraform Cloud oder S3-kompatiblem Backend
- exakter SSH-Betriebsnutzer für Kamal
- ob zusaetzlich ein Hetzner Volume fuer App-Daten verwendet wird
- wohin `pg_dump`-Backups repliziert werden
- ob Uploads in V1 sicher lokal bleiben oder früher auf Object Storage wechseln

## Konkrete nächste Schritte

1. Hetzner-Layout unter `infra/terraform/hetzner` anlegen.
2. Ansible-Grundstruktur unter `infra/ansible` anlegen.
3. `config/deploy.hetzner.yml` und `.kamal/secrets.hetzner.example` erstellen.
4. Production für lokalen Storage und SSL vorbereiten.
5. `deploy-production.yml` für GitHub Actions implementieren.
6. ersten End-to-End-Test gegen einen frischen Hetzner-Server fahren.
