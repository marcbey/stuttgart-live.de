# Hetzner Hosting Plan

Stand: 10. Maerz 2026

## Ziel

Die Anwendung soll guenstig auf Hetzner betrieben werden, ohne die Komplexitaet der bisherigen AWS-Infrastruktur.

Empfohlene Zielarchitektur:

- 1x Hetzner Cloud `CX33`
- `Ubuntu 24.04`
- `Docker + Kamal`
- `Rails + Puma + Solid Queue` im App-Container
- `PostgreSQL` lokal auf derselben VM
- `kamal-proxy` fuer TLS und Routing
- `Hetzner Backups` aktiviert
- Uploads zunaechst lokal auf Disk

Diese Architektur passt gut zum bestehenden Repo:

- `Solid Queue` laeuft bereits im Puma-Prozess: [config/puma.rb](/Users/marc/Projects/stuttgart-live.de/config/puma.rb)
- Production faellt fuer die DB bereits auf `127.0.0.1` zurueck: [config/database.yml](/Users/marc/Projects/stuttgart-live.de/config/database.yml)
- Lokaler Active Storage Service ist bereits vorhanden: [config/storage.yml](/Users/marc/Projects/stuttgart-live.de/config/storage.yml)

## Warum kein Terraform noetig ist

Fuer einen einzelnen Produktionsserver ist Terraform nicht zwingend notwendig.

Pragmatischer Ablauf:

1. Hetzner-Server anlegen
2. SSH-Key hinterlegen
3. Domain auf die Server-IP zeigen lassen
4. Docker installieren
5. PostgreSQL lokal einrichten
6. Mit Kamal deployen

Terraform wuerde erst dann klaren Mehrwert bringen, wenn z. B. mehrere Server, Staging, Floating IPs, Volumes oder Object Storage reproduzierbar verwaltet werden sollen.

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

Guenstigere Sparvariante:

- `CX23` statt `CX33`

Dann ab 1. April 2026:

- `6.49 EUR/Monat` exkl. MwSt. inkl. IPv4 und Backups

Fuer Rails + PostgreSQL + Solid Queue auf einer einzelnen Maschine ist `CX33` die sicherere Empfehlung.

## Datenbank

PostgreSQL sollte auf dem Host laufen, nicht als separater Container.

Gruende:

- weniger bewegliche Teile
- einfachere Backups
- einfachere Administration

Produktionsdatenbanken gemaess App-Setup:

- `stuttgart_live_de_production`
- `stuttgart_live_de_production_cache`
- `stuttgart_live_de_production_queue`
- `stuttgart_live_de_production_cable`

Passend zu:

- [config/database.yml](/Users/marc/Projects/stuttgart-live.de/config/database.yml)

## Uploads

V1-Empfehlung:

- lokale Uploads auf der VM
- persistentes Kamal-Volume fuer `/rails/storage`

Spaeter optional:

- Umstieg auf Hetzner Object Storage

Fuer die guenstigste Zielarchitektur ist lokaler Storage zunaechst ausreichend.

## Backups

Empfohlene Backup-Strategie:

- Hetzner Server Backups aktivieren
- taegliches `pg_dump`
- zusaetzliche Sicherung von `/rails/storage`, wenn Uploads geschuetzt werden muessen

## Migrationsplan

1. Hetzner-VM erstellen
2. Ubuntu 24.04 und SSH-Zugang einrichten
3. Docker installieren
4. PostgreSQL installieren
5. DB-User und Datenbanken anlegen
6. Kamal fuer Hetzner konfigurieren
7. Production-Secrets fuer Hetzner anlegen
8. App deployen
9. `bin/rails db:prepare` ausfuehren
10. DNS auf die Hetzner-IP umstellen
11. Backups testen

## Sinnvolle Repo-Anpassungen fuer spaeter

Wenn das spaeter umgesetzt wird, waeren diese Repo-Aenderungen sinnvoll:

- neue Deploy-Datei, z. B. `config/deploy.hetzner.yml`
- neue Secret-Datei, z. B. `.kamal/secrets.hetzner`
- `config.active_storage.service` in Production env-gesteuert machen
- Registry von ECR auf `ghcr.io` oder Docker Hub umstellen

## Empfehlung

Fuer diese Anwendung ist folgende Zielkonfiguration das beste Preis/Leistungs-Verhaeltnis:

- `CX33`
- lokale PostgreSQL-Datenbank
- lokale Uploads
- Hetzner Backups
- Kamal fuer Deployments
- kein Terraform im ersten Schritt

## Quellen

- [Hetzner Cloud](https://www.hetzner.com/cloud)
- [Hetzner Price Adjustment](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)
- [Hetzner Primary IPv4](https://docs.hetzner.com/cloud/servers/primary-ips/overview)
- [Hetzner Billing FAQ](https://docs.hetzner.com/cloud/billing/faq/)
- [Hetzner Object Storage](https://www.hetzner.com/storage/object-storage/overview/)
