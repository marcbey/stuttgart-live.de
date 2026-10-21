# Infrastruktur und Veröffentlichungen

Stand: 20. Oktober 2026

Diese Übersicht beschreibt den gemeinsamen Betrieb von Stuttgart Live und Russ
Live. Die [README](README.md#ci-staging-und-produktionsfreigabe-über-github)
erklärt die täglichen Handgriffe; das
[Betriebsrunbook](docs/operations/domainumzug-und-staging.md) behandelt
Domainwechsel, DNS-Nachweise und die Wiederaufnahme unterbrochener Host-Eingriffe.
Die Infrastruktur wird zentral aus diesem Repository verwaltet. Russ dokumentiert
seine app-spezifischen Secrets und Datenbankverbindungen in seiner
[README](https://github.com/marcbey/russ-live.de#deployment-und-betrieb).

## Gemeinsamer Host, getrennte Umgebungen

Beide Anwendungen laufen auf dem Hetzner-Host `46.225.224.194`.
Produktions- und Staging-Container teilen sich die VM, Docker, PostgreSQL und
`kamal-proxy`. Staging ist daher keine vom Produktionshost unabhängige
Ausfallumgebung. Seine Container haben eigene CPU-/RAM-Limits; bei Engpässen
hat Produktion Vorrang.

| Umgebung | Stuttgart Live | Russ Live | Kamal-Ziel |
| --- | --- | --- | --- |
| Produktion | `https://stuttgart-live.de` | `https://russ-live.de` | `hetzner` |
| Staging | `https://staging.stuttgart-live.de` | `https://staging.russ-live.de` | `staging` |

`www` leitet in Produktion mit HTTP 308 und erhaltenem Pfad sowie Querystring
auf die jeweilige Hauptdomain weiter. Staging verlangt Basic Auth und setzt
`noindex, nofollow` sowie `no-store`, auch für Assets und Medien. Nur der exakte
Healthcheck `/up` bleibt ohne Anmeldung erreichbar und prüft die Rails-Readiness.

Jede Anwendung hat je Umgebung einen eigenen Web- und einen eigenen Job-Container.
Im Web-Container liefert nginx Assets und signierte `/media/...`-Dateien direkt
aus; Puma verarbeitet Rails-Anfragen. Solid Queue läuft separat über `bin/jobs`.
PostgreSQL läuft auf dem Host und ist nicht öffentlich freigegeben. Die
Container verbinden sich über das Docker-Gateway `172.18.0.1`.

Die verbindlichen Zielprofile stehen in
[config/deploy.hetzner.yml](config/deploy.hetzner.yml),
[config/deploy.staging.yml](config/deploy.staging.yml) und den jeweiligen
`deploy.*.shared.yml`-Dateien beider Repositories. SSH-Host-Keys sind dort gepinnt;
Passwörter und private Schlüssel gehören nicht in diese Dateien.

## Datenbanken, Medien und externe Dienste

| Ressource | Produktion | Staging |
| --- | --- | --- |
| Stuttgart-Fachdatenbank | `stuttgart_live_de_production` | `stuttgart_live_de_staging` |
| Russ-Fachdatenbank | `russ_live_de_production` | `russ_live_de_staging` |
| Cache, Queue, Cable | je App eigene DBs mit Suffix `_cache`, `_queue`, `_cable` | ebenfalls je App getrennt |
| Gemeinsames Medienvolume | `stuttgart_live_de_storage` | `stuttgart_live_de_staging_storage` |
| Russ-Lesebenutzer für Stuttgart | `russ_live_de_reader` | `russ_live_de_staging_reader` |

Russ liest Events und die gemeinsame Nutzerquelle ausschließlich über seinen
Reader in der Stuttgart-Datenbank derselben Umgebung. Eigene Russ-Daten,
Sessions und Betriebsdaten liegen in den Russ-Datenbanken. Stuttgart migriert
seine Datenbanken; Russ migriert seine eigenen. Ein Restore muss die zusätzlichen
Reader-Grants wiederherstellen.

Staging hat acht eigene Datenbanken und drei eingeschränkte PostgreSQL-Rollen.
Diese dürfen keine Produktionsdatenbank öffnen. Eigene Rails-Credentials,
Session-Schlüssel und DB-Passwörter trennen die Umgebungen. Der Medien-Signierschlüssel
ist innerhalb eines Umgebungspaars gleich und zwischen Produktion und Staging
verschieden. Beide Staging-Apps verwenden weiterhin `RAILS_ENV=production`;
`APP_ENVIRONMENT=staging` aktiviert die Schutzregeln.

Staging versendet ausschließlich an Mailpit. Dessen Oberfläche ist nur auf dem
Host unter `127.0.0.1:8025` gebunden; lokal ist sie per SSH-Tunnel erreichbar.
Wiederkehrende Jobs, echte Newsletter, Meta-Veröffentlichungen, externe Imports,
kostenpflichtige KI-Aufrufe und Tracking-Pixel sind dort gesperrt.

Ein Deploy aktualisiert Code und führt die vorgesehenen Migrationen aus. Er
kopiert keine Produktionsdaten. Die gesonderte, manuell gestartete
[bereinigte Datenübernahme](README.md#bereinigte-staging-daten-manuell-erneuern)
stoppt beide Staging-Apps, ersetzt deren Daten und Medien, entfernt sensible
Inhalte und prüft Medien sowie DB-Rechte. Nur nach vollständiger Prüfung wird
`/rails/storage/.staging-ready.json` freigegeben. Bei Fehlern bleibt Staging aus.
Produktionsdaten und Produktionsmedien werden dabei ausschließlich gelesen.

## Von einer Änderung bis zur Produktion

```text
PR → PR-CI → optional manuell „Deploy PR Staging“ (gemeinsames Staging)
 ↓ Merge
main → vollständige Main-CI → Deploy Staging → Versionszusammenfassung
                                             ↓
                                   Produktionsfreigabe
                                   durch Marc oder Katharina
                                             ↓
                                   geprüftes Image auf Prod
```

Die PR-Vorschau verwendet die Deploy-Steuerung von `main` und erzeugt keine
Produktionsfreigabe. Der automatische Main-Deploy ersetzt sie nach dem Merge.
Die täglichen Schritte stehen in der
[README](README.md#ci-staging-und-produktionsfreigabe-über-github).

1. Änderungen durchlaufen PR-Prüfungen und nach dem Merge erneut die vollständige
   Main-CI. Ein erfolgreicher Main-Lauf startet `Deploy Staging` automatisch.
2. Die Main-CI baut den Commit parallel zu den vollständigen Prüfungen einmal
   und veröffentlicht ihn in GHCR. Staging übernimmt dessen Digest aus dem
   erfolgreichen CI-Lauf. Echte nginx-HTTP-Tests laufen vor Bereitstellung der
   Staging-Secrets. Nach dem Deploy werden laufende Web-/Job-Versionen, HTTPS,
   Login und Medien geprüft.
3. Die Kompatibilitätsprobe testet die konkrete Kombination mit dem anderen
   Staging-Projekt und mit dessen tatsächlich produktiver Version. Dafür werden
   nur das Schema des produktiven Peers und erneut maskierte Staging-Daten in
   einer kurzlebigen isolierten Docker-Umgebung verwendet.
4. Erst nach Erfolg entsteht das Artefakt `staging-release`. Es bindet unter
   anderem Commit, Image-Digest, CI-Lauf, Konfiguration und geprüfte Peer-Versionen.
   Die Aufbewahrung beträgt derzeit **14 Tage**.
5. Erfolgreiches Staging startet `Deploy Production` automatisch. Die Vorbereitung
   zeigt die aktuelle Produktion, den Kandidaten, den Versionsvergleich und die
   zugehörigen PRs. Anschließend wartet der Job auf **Review deployments** für
   `production`. Im Normalfall muss niemand eine Run-ID kopieren.
6. Marc (`marcbey`) oder Katharina Schopper (`kasch0`) prüft die Änderungen und
   Staging und gibt den Job frei. Eine Freigabe reicht. Beide haben Schreibzugriff,
   sind erforderliche Environment-Reviewer und dürfen auch eigene Läufe freigeben.
   Administratoren dürfen den Schutz nicht umgehen; das Ziel ist auf `main` beschränkt.
7. Produktion übernimmt exakt das geprüfte Image ohne Neubau. Vor der Mutation
   werden Nachweis, Konfiguration, Digest und der aktuelle Produktions-Peer erneut
   geprüft. Der eigene Produktionsstand muss noch der zuvor gezeigten Basis
   entsprechen; sonst ist eine neue Vorbereitung nötig.

Neuere erfolgreiche Staging-Läufe ersetzen ältere noch wartende automatische
Produktionsfreigaben. Es wird keine Warteschlange aller ausgelassenen Releases
auf Produktion nachgeholt: Die neue Version enthält die Änderungen seit dem
bisherigen Produktionsstand. Laufende Deployments und manuelle Rollback-Anfragen
werden dabei nicht automatisch abgebrochen. Wartende Freigaben halten keine
Host-Sperre und blockieren Staging oder das andere Repository nicht.

Eine reguläre Freigabe verlangt den neuesten erfolgreichen Staging-Nachweis und
dessen weiterhin laufendes Staging-Image. Hat sich der produktive Peer geändert,
muss ein frischer Kompatibilitätsnachweis erstellt werden. Fehlende, abgelaufene
oder veränderte Nachweise führen zum Abbruch.

## Manueller Rollback

Im jeweiligen Repository unter **Actions → Deploy Production → Run workflow**
Branch `main`, Modus `rollback` und die `staging_run_id` der gewünschten früheren
Version wählen. Die ID steht in der URL ihres erfolgreichen **Deploy Staging**-Laufs
(`actions/runs/…`), nicht im PR oder in der Commit-SHA. Dasselbe per CLI:

```bash
gh workflow run deploy-production.yml --ref main -f mode=rollback -f staging_run_id=RUN_ID
```

Der Rollback zeigt ebenfalls den Vergleich zur aktuellen Produktion und wartet
auf dieselbe Freigabe durch Marc oder Katharina. Er darf einen älteren Nachweis
verwenden; nur die Prüfungen auf neuesten Lauf und aktuell laufendes Staging-Image
entfallen. Digest, Konfiguration und aktueller Produktions-Peer bleiben gebunden.
Bei abgelaufenem Artefakt oder geändertem Peer zuerst einen neuen Nachweis erstellen.

**Ein Code-Rollback setzt weder Datenbankmigrationen noch Inhalte oder Uploads
zurück.** Der ältere Code muss mit dem heutigen Schema funktionieren. Ein
Datenbank-Restore ist ein eigener koordinierter Wartungseingriff. Auch der
DNS-Rückweg beim Domainumzug ist vom App-Rollback getrennt.

## Gemeinsame Sperre und Fehlerbehandlung

Die regulären Deployments beider Anwendungen und Umgebungen sowie der
Staging-Refresh verwenden `/var/lock/live-deploy/global.lock`. Die Produktionsvorbereitung hält
sie kurz beim Lesen der Versionen und Ersetzen alter Freigaben; die eigentliche
Wartezeit auf den Reviewer findet außerhalb der Sperre statt.

Bei abgebrochenen oder fehlgeschlagenen Mutationen bleibt zusätzlich die
Operationsmarkierung `/var/lock/live-deploy/active-operation` stehen. Sie sperrt
weitere Vorgänge, bis ein Administrator den tatsächlichen Prozess- und
Containerzustand geprüft hat. Es gibt keine automatische Freigabe nach Zeitablauf.
Die [gezielte Wiederaufnahme](docs/operations/domainumzug-und-staging.md#unterbrochene-host-operation-klären)
beschreibt die Prüfung und Entfernung ausschließlich der bekannten Markierung.

Manuelle Host-/DB-Eingriffe, Ansible und Terraform werden durch diese
Deploy-Sperre nicht automatisch serialisiert. Sie brauchen ein abgestimmtes
Wartungsfenster, ausgesetzte konkurrierende Deployments und eine passend gehaltene
Sperre für betroffene Host-Mutationen. Die Wrapper allein stellen das nicht sicher.

Der gemeinsame Proxy wird bei Deploy-Fehlern nicht automatisch neu gestartet.
Ein Proxy-Upgrade oder Host-Neustart betrifft alle vier App-Ziele und braucht
einen separat koordinierten Eingriff. Direkte lokale Kamal-Deploys ersetzen weder
Sperre noch Produktionsfreigabe oder Kompatibilitätsnachweis.

## Infrastruktur ändern und neu aufbauen

| Werkzeug | Verantwortung | Anleitung |
| --- | --- | --- |
| Terraform / Hetzner | VM, IPs, Firewall, SSH-Key-Registrierung, optionale Volumes und Server-Backups | [Hetzner-Stack](infra/terraform/hetzner/README.md) |
| Ansible | Host-Härtung, Docker, PostgreSQL, Rollen, Backup-Jobs und Staging-Ressourcen | [Host-Konfiguration](infra/ansible/README.md) |
| Kamal über GitHub Actions | geprüfte App-Images, Container, Routing und Release-Prüfungen | [Deployment](README.md#ci-staging-und-produktionsfreigabe-über-github) |
| GitHub-Environments | getrennte Secrets und Produktionsfreigaben | [GitHub-Stack und Grenzen](infra/terraform/github/README.md) |

Host-Administration verwendet den Benutzer `admin`, App-Deployments `deploy`.
Terraform und Ansible laufen nicht als Teil eines App-Deployments. Die Reihenfolge
für einen neuen Host ist Terraform, Ansible-Bootstrap, Produktionskonfiguration,
separates Staging-Playbook, eigene Secrets und geprüfte Datenübernahme. Danach
DB-Rechte und Readiness nachweisen und beide Deploy-Pipelines abnehmen.

Die Terraform-Defaults `cx33`, `ubuntu-24.04` und optionales Zusatzvolume
beschreiben die Provisionierung, keinen aktuellen Kapazitäts- oder
Wiederherstellungsnachweis. Das versionierte Inventory ist die Verbindung zum
bestehenden Host; vor Änderungen immer tatsächlichen Bestand und Terraform-Plan
vergleichen. Secrets, State-Dateien und private Betriebsnachweise nicht committen.

## Backups, Domainwechsel und verbleibende Nacharbeiten

Ansible konfiguriert tägliche PostgreSQL-Custom-Dumps um 03:15 Uhr unter
`/var/backups/stuttgart-live` mit sieben Tagen Aufbewahrung, einschließlich der
Russ-Datenbanken bei aktivierter Russ-Konfiguration. Die zusätzliche
Dateisicherung ist im versionierten Default mit `backup_storage_enabled: false`
ausgeschaltet. Ein persistentes Docker-Volume ersetzt kein unabhängiges Backup.
Server-Backups, aktuelle Dumps, externe Replikation und ein gemeinsamer Restore
von Datenbanken, Rollen und Medien müssen betrieblich nachgewiesen werden.
Eine erfolgreiche Wiederherstellungsprobe oder Offsite-Sicherung wird durch die
Deploy-Pipeline nicht belegt. Auch die Ablage und Sicherung des verwendeten
Terraform-States muss für den Betrieb separat festgehalten werden.

Beim Domainwechsel bleiben Mail-DNS, Microsoft 365, Mailjet-Verifizierungen,
VPN und unbekannte Einträge unverändert. Vollständige Vorher-/Nachher-Nachweise,
gezielte erlaubte Web-DNS-Änderungen und der zeitlich begrenzte WordPress-Rückweg
stehen im [Runbook](docs/operations/domainumzug-und-staging.md). Domain-/TLS-Modus
ist eine Production-Environment-Variable und wird nicht durch Staging geändert.

Beide Produktionen verwenden `PRODUCTION_DOMAIN_MODE=live` und automatisch
verwaltete HTTPS-Zertifikate im persistenten Volume `kamal-proxy-config`.
Auch `michaelrussgmbh.de` und `www.michaelrussgmbh.de` leiten seit dem 19. Oktober
mit gültigem HTTPS auf genau `https://russ-live.de/` weiter; alte Pfade und
Querystrings entfallen. Die eigene ACME-DNS-Bereinigung benötigt noch frische
Provider-Anmeldungen und vollständige Vorher-/Nachher-Nachweise.

Das mindestens 72-stündige WordPress-Rückfallfenster endete am 20. Oktober um
19:13 Uhr MESZ. Die funktionale Nutzerabnahme und die dokumentierten Messlücken
stehen im privaten Protokoll. Der bisherige WordPress-Betreiber und sein
Hostingzugang sind weiterhin unbekannt; die Abschaltung bleibt eine externe
Abhängigkeit. Der [aktuelle Betriebsstand](docs/operations/domainumzug-und-staging.md#betriebsstand-nach-dem-domainumzug)
nennt DNS-Werte, Zuständigkeiten und die noch offene Abschlussbereinigung.

## Erkenntnisse aus den Staging-Korrekturen vom 17./18. Oktober

- **Langsame Seiten:** nginx prüft Basic Auth für jedes Bild und Asset. Für das
  lange zufällige Staging-Passwort wird SHA-512-crypt verwendet; der zuvor teure
  Bcrypt-Hash bremste jeden Request. Passwort und Hash müssen weiterhin zusammenpassen.
- **Leere Bildbereiche:** `MEDIA_PROXY_ENABLED=true` muss auch in Staging gesetzt
  sein. nginx liefert signierte Medien aus dem getrennten Staging-Volume.
- **Fehlende Eventbilder nach Datenübernahme:** Die Bereinigung behält öffentliche
  `import_event_images`, die bestehenden Events gehören; Rohimport-Verweise und
  verwaiste Zeilen werden entfernt. Medienprüfung und ein Blick auf echte
  Eventkarten ergänzen den reinen Startseiten-Healthcheck.
- **Kalte Staging-Seiten:** HTTP-Leseprüfungen erlauben dort bis zu 60 Sekunden;
  Produktion behält 15 Sekunden. Das ersetzt keine Prüfung der wahrgenommenen
  Ladezeit und der geladenen Bilder im Browser.

Die ursprünglichen Pläne unter `docs/superpowers/` sind Entscheidungs- und
Implementierungshistorie. Für heutige Betriebsanweisungen gelten diese Übersicht,
die READMEs und das Betriebsrunbook.
