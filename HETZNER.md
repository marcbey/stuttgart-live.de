# Hetzner Hosting Plan

Stand: 10. März 2026

## Ziel

Die Anwendung soll günstig auf Hetzner betrieben werden, ohne die Komplexität der bisherigen AWS-Infrastruktur.

Empfohlene Zielarchitektur:

- 1x Hetzner Cloud `CX33`
- `Ubuntu 24.04`
- `Docker + Kamal`
- `Rails + Puma + Solid Queue` im App-Container
- `PostgreSQL` lokal auf derselben VM
- `kamal-proxy` für TLS und Routing
- `Hetzner Backups` aktiviert
- Uploads zunächst lokal auf Disk

Diese Architektur passt gut zum bestehenden Repo:

- `Solid Queue` läuft bereits im Puma-Prozess: [config/puma.rb](/Users/marc/Projects/stuttgart-live.de/config/puma.rb)
- Production fällt für die DB bereits auf `127.0.0.1` zurück: [config/database.yml](/Users/marc/Projects/stuttgart-live.de/config/database.yml)
- Lokaler Active Storage Service ist bereits vorhanden: [config/storage.yml](/Users/marc/Projects/stuttgart-live.de/config/storage.yml)

## Warum Terraform und Ansible sinnvoll sind

Für dieses Projekt ist `Terraform + Ansible` sinnvoll, obwohl zunächst nur ein einzelner Produktionsserver geplant ist.

Der entscheidende Grund ist die Wiederholbarkeit:

- die Infrastruktur soll später in einem anderen Hetzner-Konto neu aufgebaut werden können
- Server, Firewall, Backups, IP-Konfiguration und SSH-Setup sollen nicht manuell nachgeklickt werden müssen
- die Host-Konfiguration soll reproduzierbar und dokumentiert sein

Empfohlene Aufteilung:

1. `Terraform` provisioniert Hetzner-Ressourcen
2. `Ansible` konfiguriert den Host
3. `Kamal` deployt die Anwendung
4. `GitHub Actions` übernimmt nur CI und App-Deploy

Terraform verwaltet dabei insbesondere:

- Hetzner-Server
- SSH-Key-Registrierung
- `Primary IPv4`
- Firewalls
- Backups
- optional Volumes

Ansible verwaltet insbesondere:

- Benutzer und SSH-Hardening
- Docker
- PostgreSQL
- Datenbank-User und Datenbanken
- Backup-Jobs

## Kosten

Empfohlene Variante:

- `CX33`
- `Primary IPv4`
- `Hetzner Backups`

Vor der Hetzner-Preisanpassung am 1. April 2026:

- `CX33`: `5.49 EUR/Monat`
- `Primary IPv4`: `0.50 EUR/Monat`
- `Backups`: `1.10 EUR/Monat`

Summe:

- `7.09 EUR/Monat` exkl. MwSt.
- `8.44 EUR/Monat` inkl. 19% MwSt.

Ab 1. April 2026:

- `CX33`: `7.99 EUR/Monat`
- `Primary IPv4`: `0.50 EUR/Monat`
- `Backups`: `1.60 EUR/Monat`

Summe:

- `10.09 EUR/Monat` exkl. MwSt.
- `12.01 EUR/Monat` inkl. 19% MwSt.

Günstigere Sparvariante:

- `CX23` statt `CX33`

Dann ab 1. April 2026:

- `6.49 EUR/Monat` exkl. MwSt. inkl. IPv4 und Backups

Für Rails + PostgreSQL + Solid Queue auf einer einzelnen Maschine ist `CX33` die sicherere Empfehlung.

## Datenbank

PostgreSQL sollte auf dem Host laufen, nicht als separater Container.

Gründe:

- weniger bewegliche Teile
- einfachere Backups
- einfachere Administration

Produktionsdatenbanken gemäß App-Setup:

- `stuttgart_live_de_production`
- `stuttgart_live_de_production_cache`
- `stuttgart_live_de_production_queue`
- `stuttgart_live_de_production_cable`

Passend zu:

- [config/database.yml](/Users/marc/Projects/stuttgart-live.de/config/database.yml)

## Uploads

V1-Empfehlung:

- lokale Uploads auf der VM
- persistentes Kamal-Volume für `/rails/storage`

Später optional:

- Umstieg auf Hetzner Object Storage

Für die günstigste Zielarchitektur ist lokaler Storage zunächst ausreichend.

## Backups

Empfohlene Backup-Strategie:

- Hetzner Server Backups aktivieren
- tägliches `pg_dump`
- zusätzliche Sicherung von `/rails/storage`, wenn Uploads geschützt werden müssen

## Migrationsplan

1. Hetzner-Ressourcen mit Terraform provisionieren
2. Ubuntu 24.04 Host mit Ansible konfigurieren
3. Docker und PostgreSQL automatisiert einrichten
4. DB-User und Datenbanken anlegen
5. Kamal für Hetzner konfigurieren
6. Production-Secrets für Hetzner anlegen
7. App deployen
8. `bin/rails db:prepare` ausführen
9. DNS auf die Hetzner-IP umstellen
10. Backups testen

## Sinnvolle Repo-Anpassungen für später

Wenn das später umgesetzt wird, wären diese Repo-Änderungen sinnvoll:

- neue Deploy-Datei, z. B. `config/deploy.hetzner.yml`
- neue Secret-Datei, z. B. `.kamal/secrets.hetzner`
- `config.active_storage.service` in Production env-gesteuert machen
- Registry von ECR auf `ghcr.io` oder Docker Hub umstellen

## Empfehlung

Für diese Anwendung ist folgende Zielkonfiguration das beste Preis/Leistungs-Verhältnis:

- `CX33`
- lokale PostgreSQL-Datenbank
- lokale Uploads
- Hetzner Backups
- Kamal für Deployments
- Terraform für Provisionierung
- Ansible für Host-Konfiguration

## Quellen

- [Hetzner Cloud](https://www.hetzner.com/cloud)
- [Hetzner Price Adjustment](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)
- [Hetzner Primary IPv4](https://docs.hetzner.com/cloud/servers/primary-ips/overview)
- [Hetzner Billing FAQ](https://docs.hetzner.com/cloud/billing/faq/)
- [Hetzner Object Storage](https://www.hetzner.com/storage/object-storage/overview/)
