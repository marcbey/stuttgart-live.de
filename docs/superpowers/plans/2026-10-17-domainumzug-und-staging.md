# Domainumzug und Staging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beide Rails-Projekte unter ihren endgültigen Domains veröffentlichen, isoliertes Staging einrichten und einen geprüften Veröffentlichungs- und Rückfallweg schaffen, ohne bestehende Nicht-Web-DNS-Einträge zu verändern.

**Architecture:** Beide Projektpaare bleiben auf `46.225.224.194` mit gemeinsamem Kamal-Proxy und PostgreSQL-Dienst. Staging bildet die Produktionsarchitektur mit eigenen Datenbanken, Credentials und Medien nach; Russ liest jeweils die Stuttgart-Daten derselben Umgebung. Ein Image wird nach erfolgreicher CI zunächst auf Staging bereitgestellt und anschließend als exakt dieselbe Version manuell nach Produktion übernommen.

**Tech Stack:** Ruby 4.0.2 über mise, Rails 8.1, Kamal 2.12, Docker/GHCR, nginx, PostgreSQL, Solid Queue/Cache/Cable, Ansible, GitHub Actions, DNS bei Host Europe und STRATO; internes SMTP-Testpostfach mit Mailpit.

**Spec:** [Freigegebene Spezifikation vom 17. Oktober 2026](../specs/2026-10-17-domainumzug-und-staging-design.md), einschließlich der Ergänzung zum unveränderten Microsoft-365-DNS. Die schriftliche Spezifikation wurde im Gespräch freigegeben. Dieser Plan steht vor der Ausführung noch zur Prüfung und Auswahl der Ausführungsmethode.

## Global Constraints

- **Alle bestehenden DNS-Einträge, die nicht das Webangebot betreffen, müssen unverändert bleiben. Microsoft 365 muss während und nach dem gesamten Umzug weiterhin funktionieren.** Das gilt auch für Werte, Prioritäten und individuell konfigurierte TTLs sowie für Vorbereitung und Rückfall.
- Kein Registrar-/Nameserverwechsel, kein DNS-Zonenreset oder vollständiger Zonenimport, keine Änderung von DNSSEC oder bestehenden CAA-Regeln. Keine zusätzlichen Mailjet-DNS-Verifizierungen als Teil dieses Vorhabens.
- Neue DNS-01-Werte werden ausschließlich ergänzend unter `_acme-challenge` angelegt; vorhandene TXT-Werte bleiben erhalten. Beim Aufräumen nur selbst hinzugefügte Werte entfernen.
- Hauptdomains ohne `www`; `www` leitet einschließlich Pfad und Querystring auf HTTPS ohne `www` weiter. Alte Web-AAAA-Einträge nur mit positiv geprüfter Hetzner-IPv6-Erreichbarkeit beibehalten.
- Produktion: `stuttgart-live.de`, `russ-live.de`. Staging: `staging.stuttgart-live.de`, `staging.russ-live.de`. Kein `old.*`. `www.michaelrussgmbh.de` bleibt bis zu einem späteren separaten Schritt unverändert.
- Staging läuft mit `RAILS_ENV=production`, eigenen Datenbanken, Credentials und Medien sowie Passwortschutz und `noindex, nofollow`. Keine produktiven Nachrichten, Kontakt-Synchronisationen, Social-Media-Veröffentlichungen oder automatischen kostenpflichtigen Läufe.
- Datenaktualisierung nur manuell; Bereinigung erfolgt vor Freigabe von Zugriff und Workern. Queue, Cache und Cable werden nicht aus Produktion kopiert.
- Produktions-Zielname `hetzner` bleibt bestehen; neues Kamal-Ziel `staging`. Bestehende Produktionsdatenbanken und `stuttgart_live_de_storage` werden beim Umzug nicht ersetzt.
- Alle Ruby-/Bundler-Aufrufe auf Entwicklungs- und CI-Rechnern erfolgen über `mise exec -- ...`. Container verwenden das unveränderte, auf Ruby 4.0.2 basierende Image; ihre Verwaltung erfolgt von außen über `mise exec -- bin/kamal ...`.
- Vor jedem Push Remote-Stand holen, Branch per Fast-forward/Rebase aktualisieren, gegebenenfalls neue Migrationen anwenden und anschließend `mise exec -- bin/ci` erfolgreich ausführen. Geänderte Ruby-Dateien zusätzlich gezielt mit `mise exec -- bundle exec rubocop ...` prüfen.
- Vorhandene fremde Änderungen erhalten, nur eigene Dateien/Hunks committen. Entire-Laufzeitdaten, `.env`, Schlüssel, Klartext-Credentials, Dumps und DNS-Exporte bleiben außerhalb von Commits. Deutsche Texte verwenden echte Umlaute und `ß`.
- Beide READMEs werden im selben Implementierungsworkflow aktualisiert. Keine Änderungen an öffentlichen/backend Assets oder Fonts für dieses Betriebsvorhaben.
- Russ wird vor Stuttgart umgeschaltet. WordPress bleibt mindestens 72 Stunden nach erfolgreicher Stuttgart-Abnahme als Rückfallmöglichkeit auf dem bisherigen Hosting. Ohne Betreiberkontakt können weder ein vollständiges WordPress-Backup noch die Abschaltung zugesagt werden.

## Review Focus

1. Ein fehlendes oder widersprüchliches Umgebungsprofil darf weder Produktions-Credentials noch Produktionsdatenbanken in Staging auswählen: Task 2 prüft fehlende Profile, falsche DB-Namen und fehlende Staging-Schlüssel.
2. Ein manuell gestarteter Job oder explizit injizierter produktiver API-Client darf den Staging-Schutz nicht umgehen: Task 3 prüft Mailjet, Meta und KI auch außerhalb des Schedulers.
3. Ein abgebrochener oder falsch adressierter Refresh darf weder Produktion löschen noch unbereinigte Staging-Daten veröffentlichen: Task 6 prüft Produktionsnamen, vertauschte Medienpfade, fehlende Dateien und Fehler zwischen Restore und Bereinigung.
4. Eine veraltete Freigabe, ein geänderter Image-Tag oder zwei gleichzeitige Deployments dürfen keine ungeprüfte Version veröffentlichen: Task 7 prüft Manifest, Digest und Sperren.
5. Eine Provider-Änderung an MX/TXT/TTL beim Abschalten der Weiterleitung darf nicht unbemerkt bleiben; bestehende 301-Caches dürfen die Abnahme nicht verfälschen: Task 8 prüft DNS-Abweichungen, Task 11 prüft frische HTTP-/Browser-Aufrufe.

---

## Arbeitsorte und Dateistruktur

`S` bezeichnet `/Users/marc/Projects/stuttgart-live.de`, `R` bezeichnet `/Users/marc/Projects/russ-live.de`. Bei der Ausführung sind stattdessen die isolierten Worktree-Pfade einzusetzen. Alle folgenden Dateipfade sind relativ zum ausdrücklich genannten Repository.

| Verantwortung | Dateien |
| --- | --- |
| Frühe Auswahl von Umgebung und Credentials | S+R: neu `app/lib/deployment_environment.rb`; Änderungen an `config/application.rb`, `config/environments/production.rb` |
| Zielabhängige Deployment-Werte | S+R: `app/lib/hetzner_deploy_config.rb`, `config/deploy.yml`, `config/deploy.hetzner.yml`, `config/deploy.hetzner.shared.yml`; neu `config/deploy.staging.yml`, `config/deploy.staging.shared.yml`, `.kamal/secrets.staging.example` |
| Externe Aktionen und Testmail | S: neu `app/lib/external_action_policy.rb`; bestehende Newsletter-/Meta-/Import-/OpenAI-Clients; S+R: Mailer-Konfiguration |
| HTTPS-Hosts, Passwortschutz, nginx | S+R: `bin/production-server`, `config/nginx.conf.template`; neu `bin/render-nginx-config`, `test/ops/nginx_runtime_check.rb` |
| Host und Sperre | S: neu `infra/ansible/playbooks/staging.yml`, Rollen `staging_postgres`, `staging_support`; S+R: neu `script/ops/deploy_with_lock`, `script/ops/deploy_lock.rb` |
| Bereinigung und Datenkopie | S+R: neu `app/services/staging/data_sanitizer.rb`, `script/staging/sanitize.rb`; S: neu `bin/staging-refresh`, `script/ops/staging_refresh.rb`; S+R: `bin/docker-entrypoint` |
| Versionierte Freigabe | S+R: CI- und Deployment-Workflows; neu `script/ops/release_manifest.rb`, `script/ops/validate_promotion`, `test/lib/release_manifest_test.rb` |
| DNS-Prüfung und menschlicher Ablauf | S: neu `script/ops/dns_change_policy.rb`, `bin/dns-audit`, `docs/operations/domainumzug-und-staging.md`; S+R: `README.md` |

Keine neue Bibliothek für gemeinsame Projektlogik einführen. Die wenigen gleichen Deployment-Hilfen bleiben je Repository eigenständig und erhalten dieselben Vertragstests. Stuttgart besitzt das gemeinsame Host-Setup und den Refresh; Russ besitzt seine Bereinigungsregeln für die eigene Datenbank.

## Task 1: Aktuellen Arbeitsstand und operative Voraussetzungen erfassen

**Files:** S+R: vorhandene `AGENTS.md`, `mise.toml`, Deploy-Konfigurationen; private Bestandsaufnahme unter `tmp/domain-migration/<laufkennung>/` in S.

**Interfaces:** Produziert `baseline.json` mit tatsächlichen Image-Versionen/Digests, Hosts, Datenbank-/Volume-Zuordnungen und dem belegten Rückweg; keine Secrets. Vollständige DNS-Exporte und Backups werden separat geschützt abgelegt.

- [ ] Spezifikation und diesen Plan lesen; pro Repository `git status --short`, `git branch --show-current`, `git remote -v` und `git fetch origin` prüfen. Der lokale Stuttgart-Stand ist älter als die beobachteten Produktions-Images; niemals ungeprüft von diesem alten Anwendungsstand ausgehen.
- [ ] Mit `superpowers:using-git-worktrees` passende vorhandene Worktrees bevorzugen oder isolierte Worktrees vom aktuellen Remote-Default-Branch anlegen. Branches unter `codex/` verwenden. Den freigegebenen Dokumentstand für den Implementierer verfügbar halten, ohne den schmutzigen Hauptcheckout zu übernehmen.
- [ ] Nach neuen Migrationen lokale Datenbanken aktualisieren. Je Repository `mise exec -- ruby -v` und `mise exec -- bin/ci` ausführen; Ausgangsfehler vor weiteren Änderungen dokumentieren und beheben. Ein historischer Fehler im Entwurf vom 13. Oktober ist kein Nachweis eines heutigen Fehlers.
- [ ] Benötigte Werkzeuge prüfen: `docker info`, `docker buildx version`, `gh auth status`, `ansible-playbook --version` sowie SSH-Zugriff mit gepinntem Host-Key. Fehlende Build-/Prüfwerkzeuge vor den davon abhängigen Schritten bereitstellen; dafür keine Produktions-Runtime verändern.
- [ ] Hetzner lesend prüfen: laufende Container und Digests, Proxy, PostgreSQL-Version und Verbindungsbudget, CPU/RAM/Disk, DB-/Mediengrößen und vorhandene Backups. Ressourcenreserve auch für parallele alte/neue Container berechnen.
- [ ] Bei beiden Providern die tatsächlich autoritative Zone und vollständige Export-/Ansichtsmöglichkeit prüfen. Alle Nicht-Web-Einträge einschließlich DKIM-Selektoren, SRV und TTLs erfassen; unbekannte Einträge bleiben unverändert. Mail-Abhängigkeiten von Apex/`www` prüfen, etwa SPF-Mechanismen oder CNAME-Ziele.
- [ ] Nach Nutzerkorrektur sind die bisherigen `schopp3r.de`-Hosts während der Vorbereitung optional. Keine DNS-Rechte oder SANs für diese Hosts voraussetzen; Übergangs-HTTPS umfasst Hauptdomain und `www`.
- [ ] WordPress-Rückweg mit `curl --resolve stuttgart-live.de:443:83.169.28.13 -I https://stuttgart-live.de/` und auch `www` prüfen; Zertifikatsablauf muss den Umschalttermin plus mindestens 72 Stunden abdecken. Betreiberkontakt parallel suchen; aktuellen Rückweg und spätere Abschaltung getrennt behandeln.
- [ ] Mit dem Nutzer Umschaltfenster und Verantwortliche für DNS, Abnahme und Microsoft-365-Testpostfach festhalten. Ermittlung dieser Betriebsparameter ist Voraussetzung für Tasks 11–13.

**Ergebnis:** Aktuelle Basis und ausführbare Voraussetzungen sind belegt. Hier werden weder Domains umgeschaltet noch Produktionsprozesse angehalten.

## Task 2: Umgebungsprofile, Credentials und Kamal-Ziele trennen

**Files:** S+R: frühe Konfiguration und Deployment-Dateien aus der Dateistruktur; `bin/hetzner-check`; neu `test/lib/deployment_environment_test.rb`, `test/support/deploy_config_helper.rb`; bestehende `test/lib/hetzner_deploy_config_test.rb`, `test/lib/app_config_test.rb` in S.

**Interfaces:** `DeploymentEnvironment.name(env:, rails_env:) -> String`; `DeploymentEnvironment.credentials_paths(root:, environment:) -> Hash` mit `:content_path`, `:key_path`; `DeploymentEnvironment.validate_runtime!(env:, project:) -> true` für die Projekte `stuttgart_live_de` beziehungsweise `russ_live_de`; `HetznerDeployConfig.fetch(key, destination:, required: true)` und die bisherigen Getter mit optionalem `destination:`. Fehlende Pflichtwerte lösen einen eigenen Konfigurationsfehler aus. Der Testhelfer `render_deploy_config(destination:) -> Hash` wertet Basis- und Zieldatei mit isolierten Test-ENV-Werten aus und liefert die zusammengeführte Kamal-Konfiguration.

- [ ] Vertragstests ergänzen. Assertions unter anderem:

```ruby
assert_equal "staging", DeploymentEnvironment.name(env: { "APP_ENVIRONMENT" => "staging" }, rails_env: "production")
assert_raises(DeploymentEnvironment::ConfigurationError) { DeploymentEnvironment.name(env: {}, rails_env: "production") }
config = render_deploy_config(destination: "staging")
assert_equal "stuttgart_live_de_staging", config.dig("env", "clear", "DB_NAME") # S
refute_includes config.fetch("volumes"), "stuttgart_live_de_storage:/rails/storage"
```

- [ ] Neue Tests mit `mise exec -- bin/rails test test/lib/deployment_environment_test.rb test/lib/hetzner_deploy_config_test.rb` ausführen und erwartetes Fehlschlagen wegen der fehlenden Zieltrennung bestätigen.
- [ ] Frühe Profile `APP_ENVIRONMENT=production|staging` implementieren. Entwicklung/Test behalten ihre Rails-Umgebung. Der vorhandene Asset-Build mit `SECRET_KEY_BASE_DUMMY=1` darf ohne Laufzeit-Credentials bauen, aber keine externen Aktionen aktivieren. Dieses Build-Signal überschreibt nie ein ausdrücklich gesetztes Staging-Profil und wird beim Start langlebiger Web-/Jobprozesse abgelehnt.
- [ ] In `config/application.rb` vor dem ersten Credentials-Zugriff für Staging ausschließlich `config/credentials/staging.yml.enc` und `config/credentials/staging.key` auswählen; fehlende Datei/Schlüssel führt beim Laufzeitstart zum Fehler. Produktions-Credentials und lokale Entwicklungs-Credentials bleiben ihrer bisherigen Verwendung zugeordnet.
- [ ] Zielabhängigen Config-Cache implementieren, damit `hetzner` und `staging` im selben Prozess nicht die zuerst geladenen Werte teilen. `KAMAL_DESTINATION` bei ERB-Auswertung verwenden; beide Ziele explizit erlauben. Den Produktions-Host zunächst bei seiner bisherigen `schopp3r.de`-Adresse belassen.
- [ ] Volume-Zuordnung aus der globalen Basis in die jeweiligen Ziele verschieben. Staging setzt alle DB-Namen explizit: S `stuttgart_live_de_staging{,_cache,_queue,_cable}`; R als Lesequelle `stuttgart_live_de_staging`, eigene DBs `russ_live_de_staging{,_cache,_queue,_cable}`. Staging-Volume beider Apps: `stuttgart_live_de_staging_storage`.
- [ ] Produktionsnamen beibehalten. Staging-Rollen: `WEB_CONCURRENCY=1`, `RAILS_MAX_THREADS=2`, `JOB_CONCURRENCY=1`, `JOB_THREADS=1`, passende kleine DB-Pools. Initiale Docker-Grenzen je Webcontainer `768m`/`0.5` CPUs und je Jobcontainer `512m`/`0.25` CPUs; in Task 9 anhand von Messungen anpassen.
- [ ] `validate_runtime!` vor Laufzeit-Credentials-/Datenbanknutzung aufrufen: in Staging alle DB-Namen, Rollen, Host/Port und Storage-Zuordnungen gegen das jeweilige Profil prüfen. `DATABASE_URL` und verbindungsspezifische `*_DATABASE_URL` dort ablehnen, damit Rails die getrennten DB-Namen nicht durch eine geerbte URL überschreibt. Fehler nennen nur den betroffenen Schlüssel, nie Passwort oder vollständige URL.
- [ ] `bin/hetzner-check --destination hetzner|staging` prüft jeweils die passenden Dateien und Secrets ohne Werte auszugeben. Keine unbemerkte Auflösung einer Produktions-`.env` für Staging. App-/Shell-Hilfsskripte verwenden Ruby über mise.
- [ ] Tests erweitern: fehlender Staging-Key fällt nicht auf `master.key` zurück; DB-/Volume-Produktionsnamen und URL-Overrides werden im Staging-Profil abgelehnt; wechselnde Ziele im selben Prozess bleiben korrekt; Asset-Build bleibt möglich. Tests und RuboCop für geänderte Ruby-Dateien ausführen.
- [ ] Je Repository eigenen Commit erstellen: `feat(ops): separate production and staging deployment profiles`.

## Task 3: Staging ohne produktive Außenwirkungen betreiben

**Files:** S: neu `app/lib/external_action_policy.rb`; Änderungen an `app/services/newsletter/deliver_email.rb`, `app/services/newsletter/mailjet_client.rb`, `app/services/meta/http_client.rb`, `app/services/open_ai/responses_client.rb`, HTTP-Clients unter `app/services/importing/{eventim,easyticket,reservix,llm_enrichment}/`; `config/recurring.yml`, `app/lib/app_config.rb`, `app/helpers/application_helper.rb`, `bin/sentry-release`. S+R: `config/environments/production.rb`, Staging-Deploy-Konfiguration. Neue Tests unter `test/lib/external_action_policy_test.rb` und passende bestehende Service-/Helper-Tests in S.

**Interfaces:** `ExternalActionPolicy.require_allowed!(action:, environment:) -> true` oder `ExternalActionPolicy::Disabled`; Aktionen `:mailjet`, `:meta`, `:external_import`, `:paid_ai`. Die Aufrufer übergeben das in Task 2 validierte Umgebungsprofil. Staging-SMTP ist der interne Mailpit-Dienst, ohne Relay nach außen.

- [ ] Tests schreiben, die trotz gültig aussehender/injizierter API-Credentials echte SDK-/Netzwerkaufrufe in Staging verbieten. `require_allowed!` muss vor dem ersten Netzwerk-/SDK-Aufruf scheitern. Produktion und bestehende isolierte Test-Doubles behalten ihr Verhalten.

```ruby
test "blocks mailjet in staging independently of credentials" do
  assert_raises(ExternalActionPolicy::Disabled) do
    ExternalActionPolicy.require_allowed!(action: :mailjet, environment: "staging")
  end
end
```

- [ ] Tests zuerst rot ausführen: `mise exec -- bin/rails test test/lib/external_action_policy_test.rb test/services/newsletter/mailjet_client_test.rb test/services/meta/event_social_post_publisher_test.rb`.
- [ ] Schutz direkt an den genannten Client-Grenzen einbauen. Bei Mailjet auch Testlisten, Kontakte, Tracking-Einstellungen und Kampagnenentwürfe abdecken; Meta umfasst auch OAuth-/Token-Aktionen. Den in Task 1 aktualisierten Code auf weitere direkte externe Aufrufpfade prüfen und diese denselben Grenzen zuordnen.
- [ ] `Newsletter::DeliverEmail.call(mail, client:)` verzweigt in Staging vor `client.api_configured?` auf den internen SMTP-Versand. Test: Mail landet im Testpostfach, ein injizierter Mailjet-Client wird nicht aufgerufen. Backend-Newsletter-Vorschau bleibt lokal verwendbar; gesperrte externe Aktionen liefern einen verständlichen bestehenden Fehlerpfad.
- [ ] Mailpit einmal als Stuttgart-Staging-Accessory betreiben, nur im Docker-Netz auf SMTP `1025`; Vorschauoberfläche ausschließlich an Host-Loopback `127.0.0.1:8025`, Zugriff per SSH-Tunnel. Image bei Einrichtung auf geprüften Digest pinnen, Speicher auf `128m` und Aufbewahrung auf höchstens 1.000 Nachrichten begrenzen. Keine weitere öffentliche Domain einführen.
- [ ] Beide Staging-Ziele setzen `SOLID_QUEUE_SKIP_RECURRING=true`; Worker für manuelle lokale Aufgaben bleiben vorhanden. Test für ausgelassenen Scheduler und manuell ausgelöste gesperrte Jobs hinzufügen. Die installierte Solid-Queue-Version unterstützt diese Variable.
- [ ] Die vorhandene Sentry-Integration und ihre Release-Meldungen in S verwenden `staging`; keine produktiven Analytics-/Meta-Pixel aus Staging senden. Tests prüfen den tatsächlich gewählten Environment-Wert und die unterdrückten öffentlichen Tracking-Integrationen. Für R wird hierfür keine neue externe Fehlererfassung eingeführt.
- [ ] Alle betroffenen Tests grün ausführen und geänderte Ruby-Dateien mit RuboCop prüfen. Commit: `feat(staging): isolate external actions and capture test mail`.

## Task 4: Hosts, kanonische URLs und Staging-Passwortschutz umsetzen

**Files:** S+R: `bin/production-server`, neu `bin/render-nginx-config`, `config/nginx.conf.template`, `config/environments/production.rb`, `test/lib/nginx_config_test.rb`, neu `test/ops/nginx_runtime_check.rb`; S zusätzlich `config/routes.rb`, `app/controllers/public/legacy_blog_redirects_controller.rb`, `test/controllers/public/legacy_blog_redirects_controller_test.rb` nach erfasster URL-Liste.

**Interfaces:** Render-Schritt liest `APP_HOST`, `APP_ALLOWED_HOSTS`, `CANONICAL_REDIRECT_ENABLED`, `APP_ENVIRONMENT`, `STAGING_BASIC_AUTH_HTPASSWD`, `MEDIA_PROXY_SECRET`. Er erzeugt `/tmp/nginx.conf` und gegebenenfalls `/tmp/staging.htpasswd` mit restriktiven Rechten; keine Secrets im Log. Runtime-Test erhält das gebaute Image über `APP_IMAGE`.

- [ ] HTTP-Verhalten im Runtime-Test festlegen: `www` und späterer Legacy-Host leiten bei aktivierter Umschaltung mit Status 308 auf den fest konfigurierten HTTPS-Host; Pfad/Query einschließlich URL-Encoding und die HTTP-Methode bleiben erhalten; `/up` bleibt als exakte Healthcheck-Ausnahme erreichbar. Ein fremder Host wird abgewiesen und nie als Redirect-Ziel übernommen.
- [ ] Im selben Test für Staging ohne/mit Basic Auth HTML, `/assets/...`, `/media/...`, `sitemap.xml`, 404 und `/up` prüfen. Passwortschutz gilt auch vor statischen Antworten; `noindex, nofollow` bleibt auch auf Fehlerantworten erhalten. Mit fremdem Media-Signierschlüssel muss der Abruf scheitern.
- [ ] Tests zunächst gegen das bisherige Image ausführen; neue Redirect-/Auth-Fälle müssen fehlschlagen. Der Runtime-Test startet das echte nginx-Template aus dem Image isoliert mit Testdateien und einem lokalen Test-Upstream, ohne Produktionsdaten oder Produktions-Secrets. Er ist ein verpflichtender Nach-Build-Check in Task 7. Sein Dateiname endet bewusst nicht auf `_test.rb`, damit der normale Rails-Testlauf vor dem Image-Build ihn nicht versehentlich startet; im Nach-Build-Check darf er nicht übersprungen werden.
- [ ] Config-Rendering aus dem Startskript extrahieren. Nur explizite eigene ENV-Platzhalter mit `envsubst` ersetzen; nginx-Variablen wie `$request_uri` nicht versehentlich expandieren. Kanonische Weiterleitung erfolgt vor den statischen/media Location-Blöcken und verwendet keine benutzergesteuerte Zieladresse.
- [ ] Staging-Auth und Indexierungsschutz aus dem validierten Staging-Profil zwingend aktivieren; fehlender Auth-Hash verhindert den Start. `/up` gibt keine Nutzdaten aus und ist die einzige öffentliche Auth-Ausnahme. Produktions-Session-Cookies erhalten keine Domainfreigabe für Staging.
- [ ] Produktions-Redirects zunächst deaktiviert lassen. Vorbereitung und öffentlicher Wechsel werden über das erfasste Laufzeitprofil gesteuert: `APP_HOST`/Hosts, Redirect-Flag, `STAGING_NOINDEX`, TLS-Modus. Der Image-Inhalt bleibt dabei unverändert. Das vollständige Profil wird je Deployment dokumentiert.
- [ ] Bestehende Signaturverfahren für Medien erhalten. Innerhalb einer Umgebung verwenden S und R denselben Medien-Signierschlüssel; Staging verwendet einen anderen als Produktion. Alte bereits versandte Produktions-Funktionslinks behalten ihre Schlüssel.
- [ ] Nach Build mit gesetztem `APP_IMAGE` den Befehl `mise exec -- ruby test/ops/nginx_runtime_check.rb` ausführen; alle Fälle müssen bestehen. Zusätzlich Rails-Host-/Legacy-Tests und RuboCop ausführen. Commit je Repository: `feat(ops): add canonical hosts and protected staging access`.

## Task 5: Isolierte Host-Ressourcen und eine gemeinsame Deploy-Sperre bereitstellen

**Files:** S: neu `infra/ansible/playbooks/staging.yml`, `infra/ansible/roles/staging_postgres/tasks/main.yml`, `infra/ansible/roles/staging_postgres/defaults/main.yml`, `infra/ansible/roles/staging_postgres/handlers/main.yml`, `infra/ansible/roles/staging_support/tasks/main.yml`, `script/ansible_app_host_staging`; Änderungen an `infra/ansible/README.md`. S+R: neue Sperr-Hilfen, neu `script/ops/check_staging_acl.rb`. Tests: S neu `test/lib/staging_inventory_test.rb`, S+R neu `test/lib/deploy_lock_test.rb`.

**Interfaces:** Host-Sperre `/var/lock/live-deploy/global.lock` für beide Apps und beide Umgebungen. `Ops::DeployLock.with_lock(host:, key_path:, timeout: 900, &block)` hält eine SSH-/`flock`-Sitzung während des gesamten Blocks offen und gibt sie bei Erfolg/Fehler frei. Der CLI-Wrapper reicht den Exitcode des verwalteten Kommandos weiter. `check_staging_acl.rb` wird als Rails-Runner mit den tatsächlichen Stage-Verbindungsdaten ausgeführt und liefert Exit 0 nur bei korrekten Positiv-/Negativprüfungen, ohne Datensätze oder Secrets auszugeben.

- [ ] Tests schreiben: zwei Prozesse können den geschützten Block nicht gleichzeitig betreten; Timeout verhindert die Ausführung; Ausnahme/SSH-Abbruch beendet den Deploy und gibt die Sperre frei. Kein produktives SSH-Ziel in diesen Tests verwenden.
- [ ] `staging_postgres` legt nur Staging-Rollen und acht Staging-Datenbanken an. Rollen: `stuttgart_live_de_staging`, `russ_live_de_staging_reader`, `russ_live_de_staging`; keine Superuser-, Rollen- oder DB-Erstellungsrechte. Der Reader erhält nur `SELECT`/Schema-Zugriff auf Stuttgart-Staging und passende Default-Grants für neue Tabellen.
- [ ] Rollenparameter in `staging_postgres/defaults/main.yml` festlegen; Secret-Parameter heißen `staging_stuttgart_db_password`, `staging_russ_reader_password`, `staging_russ_operational_password`. Der neue Aufruf `script/ansible_app_host_staging --vars-file PATH` liest eine geschützte Variablendatei und übergibt deren Pfad an Ansible; er übernimmt weder Produktionspasswörter noch gibt er Secret-Werte über Kommandoargumente aus.
- [ ] PostgreSQL-HBA erlaubt diesen Rollen aus dem Docker-Netz ausschließlich die passenden Staging-Datenbanken und lehnt andere Ziele ab; vorhandene Produktionszugriffe bleiben funktionstüchtig. Änderungen durch Reload aktivieren. Der vorhandene breite Produktions-Playbooklauf ist nicht der Weg zur Staging-Einrichtung.
- [ ] `staging_support` erstellt das neue Medienvolume und das Sperrverzeichnis mit passenden Rechten. Keine Produktionsvolumes neu initialisieren; Geheimnisse per geschützter Variablendatei/STDIN übergeben und Ansible-Ausgaben mit `no_log` schützen.
- [ ] Wrapper und späterer Refresh benutzen dieselbe Sperre. Normale Deployment-Workflows führen keinen eigenmächtigen gemeinsamen Proxy-Neustart aus; inkompatible Proxy-Version bedeutet Abbruch und einen separat koordinierten Host-Eingriff.
- [ ] Ansible-Syntax mit `ansible-playbook -i infra/ansible/inventories/production/hosts.yml infra/ansible/playbooks/staging.yml --syntax-check` prüfen. ACL-Prüfskript für die spätere Host-Abnahme erstellen: Stage-Reader darf Event lesen, nicht schreiben; Stage-Rollen dürfen Produktionsdatenbanken nicht lesen. Schreib-Negativprüfungen verwenden Statements mit `WHERE FALSE` in zurückgerollten Transaktionen, sodass selbst bei fehlerhaften Rechten keine Inhalte verändert werden. Bisherige Produktionsberechtigungen werden separat lesend geprüft.
- [ ] Tests mit `mise exec -- bin/rails test test/lib/staging_inventory_test.rb test/lib/deploy_lock_test.rb` in S und dem Lock-Test in R rot/grün dokumentieren; Ruby-Dateien linten. Der tatsächliche ACL-Nachweis erfolgt nach Bereitstellung/Befüllung in Task 9 und ist Voraussetzung des Livegangs. Commit S: `feat(infra): provision isolated staging resources`; Commit Sperr-Hilfen S+R: `feat(ops): serialize shared-host deployments`.

## Task 6: Manuellen Refresh mit Bereinigung und gesperrtem Zwischenzustand implementieren

**Files:** S+R: neue Sanitizer/Runner aus der Dateistruktur und `bin/docker-entrypoint`; S: neue Refresh-Hilfen. Tests S+R: `test/services/staging/data_sanitizer_test.rb`; S zusätzlich `test/lib/staging_refresh_test.rb`.

**Interfaces:** `Staging::DataSanitizer.call(connection:) -> Hash<String, Integer>` arbeitet ohne externe Aufrufe/Callbacks. `mise exec -- bin/staging-refresh --snapshot MANIFEST` zeigt standardmäßig nur den Plan; `--execute` führt ihn unter der gemeinsamen Sperre aus. Zielnamen und Zielvolume sind eine feste Allowlist. Readiness-Datei: `/rails/storage/.staging-ready.json`, erst nach erfolgreicher Bereinigung beider DBs atomisch geschrieben.

- [ ] Tests erstellen: Produktions-DB als Ziel, Produktionsvolume als Ziel, gleiche Quelle/Ziel und unbekannte Datenbanknamen werden vor jedem schreibenden Aufruf abgewiesen. Fehlende Medien, Restore-Fehler oder Sanitizer-Fehler lassen Readiness fehlen und Staging gestoppt. Dry-Run führt keine Mutation aus.
- [ ] Sanitizer mit Beispieldaten testen: echte Nutzer-/Newsletter-Adressen und Passwort-Digests verschwinden, Session-/Login-Daten und Tokens sind entfernt; Event-IDs, Veröffentlichungsfreigaben und Medienzuordnungen bleiben erhalten. Zweiter Durchlauf ist ebenfalls sicher.
- [ ] In Stuttgart Nutzer-IDs wegen bestehender Fremdschlüssel behalten, aber E-Mails nach `user-<id>@example.invalid`, Namen und Passwort-Digests durch neue synthetische Werte ersetzen. `blog_posts.author_name` bereinigen. Sessions, Login-Versuche, Newsletter-Einwilligungen und Abonnenten samt Verknüpfungen entfernen; externe Newsletter-/Segment-/Kampagnen-IDs zurücksetzen.
- [ ] Social-Tokens und externe Verbindungen ohne Entschlüsselung löschen: zunächst abhängige Publish-Versuche, dann Social-Posts/Targets/Verbindungen in FK-kompatibler Reihenfolge. Import-Fehler, Raw-Payloads und Laufprotokolle bereinigen; vorher abhängige optionale Referenzen wie `event_llm_enrichments.source_run_id` lösen. `import_sources.active=false`, beide Import-Settings-JSONs `{}` und die App-Setting-Werte `daily_raw_import_enabled`, `daily_merge_import_enabled`, `daily_llm_enrichment_enabled` auf `false` setzen. Aktuelles Schema vor Umsetzung auf weitere private freie Text-/JSON-Felder prüfen und im Sanitizer explizit behandeln.
- [ ] In Russ ausschließlich über `RussRecord.connection` die eigene DB bereinigen: Sessions/Login-Versuche entfernen; Kontaktdaten durch synthetische Angaben ersetzen. Gemeinsame Nutzer werden ausschließlich im Stuttgart-Staging bereinigt. Genau einen neuen Staging-Admin über Stuttgart mit eigenem geheimem Passwort anlegen; Russ meldet sich gegen diese bereinigte Lesequelle an. Der Runner validiert den tatsächlichen Datenbanknamen seiner Verbindung vor der ersten Mutation.
- [ ] Refresh-Orchestrierung implementieren: Stage-Web/Jobs stoppen und Readiness entfernen; fachliche S-/R-Dumps ohne Produktions-Owner/ACLs in die exakten Ziel-DBs einspielen; Medien ausschließlich ins Stage-Volume kopieren; mit den je App vorgesehenen Image-Versionen bereinigen/migrieren. Queue/Cache/Cable frisch erstellen und Stage-Grants erneut anwenden.
- [ ] Für die Quellkopie konsistente Dumps je Datenbank und zwei Medien-Kopierdurchläufe verwenden; alle referenzierten Dateien anschließend prüfen. Produktion wird für den Refresh nicht gelöscht oder zurückgesetzt. Fehlen Referenzen, wird die Kopie erneut erstellt und Staging bleibt offline. Snapshot und aktuelle Code-Schemaversion müssen zusammenpassen.
- [ ] Vor der abschließenden Readiness Nutzer-/Token-/Medienprüfungen und beide App-Verbindungen ausführen. Startskripte verweigern Stage-Web/Jobs ohne Readiness-Datei oder bei unpassender Zielzuordnung; reine Offline-Sanitizer dürfen ohne diese Datei laufen. Ein fehlgeschlagener Refresh startet keine alten Worker automatisch neu.
- [ ] Tests mit `mise exec -- bin/rails test test/services/staging/data_sanitizer_test.rb test/lib/staging_refresh_test.rb` in S und dem Sanitizer-Test in R grün ausführen. Den FK-Erhalt mit realen Testdatenbanken prüfen, Ruby-Dateien linten. Commits: `feat(staging): add guarded and sanitized data refresh`.

## Task 7: CI, Image-Nachweis und manuelle Produktionsfreigabe verbinden

**Files:** S+R: `.github/workflows/ci.yml`, `.github/workflows/deploy-production.yml`; neu `.github/workflows/deploy-staging.yml`, Release-/Promotion-Hilfen und `test/lib/release_manifest_test.rb`.

**Interfaces:** Release-Manifest JSON: `schema_version`, `repository`, `commit`, `image`, `digest`, `ci_run_id`, `staging_run_id`, `deployment_config_sha256`, `paired_app_commit`, `compatible_peer_commits`. `Ops::ReleaseManifest.validate!(manifest:, expected_repository:, ci_run:, staging_run:, registry_digest:, peer_production_commit:)` verweigert ungültige Nachweise. Produktion wird ausschließlich per `workflow_dispatch` mit `staging_run_id` gestartet.

- [ ] Tests für fremdes Repository, fehlgeschlagene CI, PR-/Fork-Run statt Main-Push, andere Commit-SHA, veränderten Digest, abgelaufenen/fehlenden Staging-Nachweis und fehlende Kompatibilität zum anderen Projekt schreiben. Erwartung jeweils Abbruch vor Deploy; gültiger älterer konkret geprüfter Stand bleibt zulässig.
- [ ] CI in beiden Repositories auf vollständige erfolgreiche Prüfungen für Pull Requests und `main` ausrichten. Den Projekt-Ruby-Pin über mise verwenden; `mise exec -- bin/ci` bleibt die gemeinsame lokale Prüfinstanz. Keine Tests oder Sicherheitsprüfungen beim Umbau verlieren.
- [ ] Staging-Workflow startet nach abgeschlossenem `Main Checks` in S beziehungsweise `CI` in R. Er akzeptiert nur erfolgreiche Runs für `push` auf `main` aus demselben Repository und checkt exakt `workflow_run.head_sha` aus; keine privilegierte Ausführung von PR-/Fork-Code.
- [ ] Einmalig Image bauen, mit Commit-SHA taggen und Build-Digest festhalten. Die nginx-Runtime-Tests aus Task 4 gegen dieses Image ausführen. Erst danach Stage-Secrets laden und unter der gemeinsamen Sperre dieselbe Version mit `mise exec -- bin/kamal deploy -d staging --skip-push --version <commit>` ausrollen.
- [ ] Laufenden Image-Digest, HTTP-Smokechecks und die aktuell gemeinsam getestete App-Kombination festhalten. Zusätzlich die Kompatibilität zur tatsächlich laufenden Produktionsversion des anderen Projekts prüfen und deren Commit in `compatible_peer_commits` aufnehmen. Bei Schemaabweichungen eine isolierte Daten-/Schema-Kopie und die betroffenen App-Images verwenden, niemals Stage-Credentials für Produktionszugriff freischalten. Ein anderer Peer-Commit braucht einen neuen Nachweis; bloße Gleichheit zum Staging-Peer ist keine Pflicht und darf die Reihenfolge beider Veröffentlichungen nicht blockieren. Manifest erst nach diesen Prüfungen als Workflow-Artefakt ablegen; erfolgreiche vollständige Run-Conclusion ist Teil des Freigabenachweises.
- [ ] Production-Workflow entfernt den bisherigen automatischen `push: main`-Trigger. Er validiert den gewählten Staging-Run und sein Artefakt per GitHub-API, checkt den Manifest-Commit aus und vergleicht den aktuellen Registry-Digest mit dem geprüften Digest. Fehlende Artefakte führen zu einer klaren Ablehnung, niemals zu einem Neubau.
- [ ] Danach mit Production-Environment-Secrets, aufgezeichnetem Zielprofil und globaler Sperre `mise exec -- bin/kamal deploy -d hetzner --skip-push --version <manifest-commit>` ausführen. Nach Deploy den laufenden Digest erneut nachweisen. Retry behält Ziel, Version und Digest; kein Rückfall auf `latest` oder bloßes Runner-HEAD.
- [ ] GitHub-Environments `staging`/`production` trennen; Artifacts enthalten keine Secrets. Quell-CI und Staging-Run bleiben nachvollziehbar. Deployment-Variablen für den Domainwechsel dürfen nur die dokumentierten Laufzeitwerte ändern und werden im Laufprotokoll erfasst. Sentry-Meldung nennt das tatsächliche Ziel.
- [ ] Tests zuerst rot, dann grün ausführen; Workflow-Syntax mit vorhandenem Actionlint oder einer lokal verfügbaren gleichwertigen Prüfung kontrollieren, Ruby-Dateien linten. Commit je Repository: `feat(ci): promote verified staging images to production`.

## Task 8: DNS-Änderungen begrenzen und den Betriebsablauf dokumentieren

**Files:** S: neue DNS-Hilfen und `test/lib/dns_change_policy_test.rb`, neu `docs/operations/domainumzug-und-staging.md`; S+R: `README.md`. Private Betriebsdateien bleiben unter `tmp/domain-migration/<laufkennung>/`.

**Interfaces:** `Ops::DnsChangePolicy.violations(before:, after:, allowed_changes:) -> Array<String>`; `mise exec -- bin/dns-audit --before FILE --after FILE --allow FILE` liefert Exit 0 nur ohne unerlaubte Abweichung. Datensätze enthalten `name`, `type`, `value`, `priority`, `ttl`; TXT-RRsets werden als Wertmengen verglichen, SOA-Seriennummern separat behandelt.

- [ ] Tests mit synthetischen Zonen schreiben: Änderung von MX, SPF-/DKIM-/DMARC-TXT, Autodiscover-CNAME, SRV oder deren TTL wird abgelehnt; unbekannte bestehende Einträge sind ebenfalls geschützt. Erlaubte A-/AAAA-/`www`-Änderungen sowie ausschließlich ergänzte eigene ACME-Werte bestehen. Entfernung eines fremden ACME-Werts scheitert; allein eine neue SOA-Seriennummer besteht.

```ruby
test "rejects a Microsoft 365 MX change even during a web cutover" do
  mx = { "name" => "stuttgart-live.de", "type" => "MX", "value" => "stuttgartlive-de02c.mail.protection.outlook.com", "priority" => 0, "ttl" => 21_600 }
  changed = mx.merge("value" => "other.example.invalid")
  refute_empty Ops::DnsChangePolicy.violations(before: [mx], after: [changed], allowed_changes: [])
  assert_empty Ops::DnsChangePolicy.violations(before: [mx], after: [mx], allowed_changes: [])
end
```

- [ ] CLI und Vergleich implementieren; einen vollständigen Providerexport beziehungsweise eine vollständig erfasste Verwaltungsansicht in dieses Format normalisieren. Keine scheinbar vollständige Mail-Prüfung nur anhand bekannter `dig`-Namen: unbekannte DKIM-Selektoren und weitere Dienste müssen im Export enthalten sein.
- [ ] Einen fallbezogenen Änderungsnachweis anlegen: ursprüngliche Werte und TTLs, erlaubte Sollwerte, DNS-Operator, Zeitpunkt, zugehörige Zertifikats-/App-Version und gezielter Rückweg. Der Bericht enthält keine Logins oder privaten Schlüssel.
- [ ] Erlaubte Web-Änderungen im Runbook festlegen: Apex A → `46.225.224.194`; `www` CNAME → jeweiliger Apex, soweit keine dokumentierte Web-Sonderkonfiguration entgegensteht; `staging` A → `46.225.224.194`; alte Web-AAAA ohne positiven IPv6-Nachweis entfernen. Keine `old.*`-Einträge. Für Russ zusätzlich den bisherigen Weiterleitungsschalter dokumentieren.
- [ ] Nur betroffene Web-TTLs auf 300–600 Sekunden absenken. Kann der Provider dies nur global, nichts absenken und die vorhandene maximale Web-TTL abwarten. SOA-/Mail-TTLs nicht ändern. Vor dem Cutover sowohl autoritative Antworten als auch Provideransicht prüfen.
- [ ] Den unten stehenden Rückfallablauf, HTTPS-Vorabtests, Microsoft-365-Abnahme und das Entfernen lokaler hosts-Einträge in das Runbook übernehmen. Beide READMEs knapp auf den neuen Alltag und das gemeinsame Runbook ausrichten, ohne bestehende fremde README-Änderungen zu überschreiben.
- [ ] Tests mit `mise exec -- bin/rails test test/lib/dns_change_policy_test.rb` grün ausführen und Ruby-Dateien linten. Commits: `feat(ops): audit scoped DNS changes` und je Repository `docs(ops): document staging promotion and domain cutover`.

## Task 9: Vorbereitung prüfen und Staging erstmals bereitstellen

**Files/Orte:** Fertige Implementierungsbranches beider Repositories, GitHub-Environments, Hetzner, neue Staging-DNS-Einträge; privates Abnahmeprotokoll.

**Interfaces:** Verwendet Profile, Sperre, Refresh und Image-Nachweise aus Tasks 2–8. Produziert zwei erreichbare und bereinigte Staging-Apps sowie ein geprüftes Versionspaar.

- [ ] In beiden Branches Remote-Stand erneut holen und aktualisieren. Neue Migrationen lokal anwenden; `mise exec -- bin/ci`, gezieltes RuboCop und erforderliche Zusatzprüfungen erneut vollständig erfolgreich ausführen. Erst danach Branches pushen und Code-Review durchführen. Änderungen bleiben bis zur koordinierten Bereitstellung gemeinsam auf den Vorbereitungsbranches.
- [ ] Staging-Secrets unabhängig erzeugen: `mise exec -- bin/rails credentials:edit --environment staging`. Nur benötigte Test-/Encryption-/Sentry-Werte aufnehmen. Keine Produktions-Credentials kopieren. Neue Session-Secrets je App und ein gemeinsamer neuer Media-Proxy-Schlüssel für das Staging-Paar. GitHub-Secrets je Environment richtig zuordnen; lokale Secret-Resolver entsprechend einrichten.
- [ ] Den separaten Ansible-Staging-Lauf zuerst mit Check-Modus prüfen, dann gezielt anwenden. Produktions-DB-/Volume-/Benutzerzustand vor und nach dem Lauf vergleichen. Die unmittelbare Verbindungsisolation prüfen; Tabellenberechtigungen folgen nach der Befüllung.
- [ ] Aktuelle rückspielbare fachliche DB-/Medienbackups außerhalb der laufenden App-Ressourcen bereitstellen. Stage-Images aus den vollständig geprüften Vorbereitungsständen einmalig bauen/pushen, etwa mit `mise exec -- bin/kamal build push -d staging`; Commit und Digest protokollieren. Diese Bootstrap-Images werden nicht für Produktion freigegeben.
- [ ] Mailpit starten; `mise exec -- bin/staging-refresh --snapshot <privates Manifest>` als Dry-Run prüfen und anschließend mit `--execute` ausführen. Das Manifest nennt die tatsächlichen Source-Backups und die beiden Bootstrap-Images. Erste Bereinigung vor Veröffentlichung bestätigen; Readiness und leere Operational-Datenbanken prüfen. Danach über `mise exec -- bin/kamal app exec -d staging` die Rails-Runner-Prüfung `script/ops/check_staging_acl.rb` je App im tatsächlichen Container-Kontext ausführen; sämtliche Rechteprüfungen müssen bestehen.
- [ ] Nur neue Staging-A-Einträge ergänzen; DNS-Vorher-/Nachher-Abgleich bestehen lassen. Beide Staging-Apps mit ihrem jeweiligen Image und `-d staging` starten. HTTPS, Auth, Medien, Russ-Freigaben, gemeinsamer Testlogin und internes Testpostfach abnehmen.
- [ ] Stage-Web/Jobs und einen rollenden Deploy gemeinsam beobachten: keine OOM-Ereignisse, ausreichende PostgreSQL-Verbindungen und mindestens 1 GiB verfügbare RAM-Reserve sowie 10 GiB freier Speicher nach Kopie. Bei Unterschreitung Staging reduzieren/stoppen und Grenzen anpassen; notwendige Config-Änderungen erneut prüfen.
- [ ] Erst bei vorhandenen Ressourcen, Secrets und bereinigten Daten die Vorbereitungsänderungen koordiniert nach `main` übernehmen. Der bisherige Production-Push-Trigger wird dabei durch den fertigen manuellen Weg ersetzt. Beide regulären Main-CI-/Staging-Läufe bestehen lassen und deren Manifeste abnehmen.
- [ ] Eine manuelle Veröffentlichung genau dieser regulären Staging-Versionen auf die bestehenden Produktions-`schopp3r.de`-Hosts durchführen und vergleichen: gleicher Image-Digest, Produktionsdaten unverändert, bisherige Hosts weiterhin nutzbar. Damit ist der neue Veröffentlichungsweg vor dem Domainwechsel praktisch geprüft.

## Task 10: Produktions-HTTPS, URL-Abbildung und Integrationen vorab prüfen

**Files/Orte:** Laufzeitprofile, Secret-Verwaltung, Provider-DNS, privater URL-/Zertifikatsnachweis.

**Interfaces:** Liefert gültige Übergangszertifikate und getestete neue Hostrouten; benutzt ausschließlich die erlaubten DNS-Änderungen aus Task 8.

- [ ] Vorhandene wichtige Stuttgart-URLs und benötigte Newsletter-/Meta-/Search-Console-/Analytics-Domainbindungen erfassen. Notwendige Code-Weiterleitungen über denselben CI→Staging→Freigabe-Weg veröffentlichen; keinen pauschalen Stringersatz externer URLs durchführen.
- [ ] CAA und die vollständigen erforderlichen DNS-Rechte prüfen. Übergangszertifikat pro Projekt mit SANs Hauptdomain und `www` per DNS-01 ausstellen. Nur neue ACME-TXT-Werte hinzufügen; vorhandene Werte nicht ersetzen. Wenn CAA oder fehlende Rechte das verhindern, TLS-Schritt anhalten und den Konflikt klären, ohne geschützte DNS-Einträge anzupassen.
- [ ] Zertifikate/Schlüssel außerhalb von Git über Kamal-Secrets bereitstellen. Proxy im Modus `prepared` mit Hauptdomain und `www` und benutzerdefiniertem Zertifikat vorbereiten; kanonische Weiterleitung bleibt aus und Indexierungsschutz bleibt bis zum jeweiligen Wechsel erhalten. Die bisherigen schopp3r-Hosts dürfen dabei entfallen. Das vorbereitete Image ist dasselbe geprüfte Image, nur das dokumentierte Laufzeitprofil wird erweitert.
- [ ] Für alle vorbereiteten Hosts `curl --resolve <host>:443:46.225.224.194 -I https://<host>/` ausführen, dazu repräsentative Events und Medien. Richtige App, Zertifikat, neue Hostrouten und Healthchecks prüfen. Canonical-/`www`-Umschaltverhalten ist bereits mit dem echten nginx aus Task 4 getestet.
- [ ] Vorhandenen verifizierten Mailabsender feststellen; benötigte Domainbindungen/Callbacks aktualisieren, ohne Mail-DNS zu verändern. Reicht die bestehende Absenderverifizierung nicht, den Mailteil als Konflikt klären statt zusätzliche SPF/DKIM-Einträge einzurichten. Bereits versandte Links und vorbereitete Newsletter-Drafts gesondert prüfen.
- [ ] Vollständigen DNS-Abgleich nach Zertifikatsvorbereitung bestehen lassen. Microsoft-365-Testpostfach durch den Nutzer/ausdrücklich beauftragten Verantwortlichen auf Senden, Empfangen und Autodiscover testen lassen; Ergebnis vor dem Cutover protokollieren.

## Task 11: Russ Live bei STRATO umschalten

**Interfaces:** Voraussetzung sind grüne Tasks 9–10 und ein vereinbartes Fenster. Stoppt bei jedem Fehler; Stuttgart bleibt bis zur vollständigen Russ-Abnahme unverändert.

- [ ] Laufende Version/Digest, aktuelle Web-DNS-Werte, Weiterleitungseinstellung und Nicht-Web-DNS-Abgleich unmittelbar vor dem Wechsel sichern. Konkurrierende Deployments und Kampagnen für das Fenster aussetzen.
- [ ] Unter globaler Sperre das geprüfte Russ-Image mit öffentlichem Laufzeitprofil bereitstellen: `APP_HOST=russ-live.de`, erlaubte Hosts mit Hauptdomain und `www`, kanonische Weiterleitung aktiv, globaler Produktions-`noindex` aus. Gültiges Übergangszertifikat verwenden. Profil und Image-Digest protokollieren.
- [ ] In STRATO nur die externe Weiterleitung ablösen, Apex A auf `46.225.224.194` setzen, alten Web-AAAA entfernen und `www` prüfen. Kontrollieren, ob das Speichern Nebenwirkungen auf andere Einträge verursacht hat; anschließend `bin/dns-audit` gegen den gesicherten Zustand bestehen lassen.
- [ ] Autoritative Nameserver sowie unabhängige Resolver abfragen. Mit frischem Browserprofil und HTTP-Client testen: richtige Startseite, `/unternehmen`, `/referenzen`, `/jobs`, Event-/Medienzugriff und Anmeldung. Alte Browser-301-Caches nicht als Zustand des neuen Servers interpretieren.
- [ ] `https://www.russ-live.de/unternehmen?probe=1` muss nach `https://russ-live.de/unternehmen?probe=1` weiterleiten; Hauptdomain darf keine Schleife erzeugen. Assets/Medien und falsche Hosts ebenfalls prüfen. Globale öffentliche Indexierbarkeit kontrollieren.
- [ ] Nach propagiertem Web-DNS von Custom-TLS auf Kamal-Automatik umstellen und gültige Zertifikate aller bedienten Hosts bestätigen. Erst nach erfolgreicher Ausgabe/Erneuerungszuständigkeit das Übergangsmaterial entfernen.
- [ ] Microsoft-365-DNS erneut vergleichen und den vereinbarten Postfach-Test wiederholen lassen. Erst nach dokumentiert erfolgreicher Russ-Abnahme Task 12 beginnen. `www.michaelrussgmbh.de` bleibt unverändert.

## Task 12: Stuttgart Live bei Host Europe umschalten

**Interfaces:** Verwendet denselben geprüften Ablauf wie Task 11 mit Stuttgart-Werten und dem zusätzlichen WordPress-Rückweg. Startet erst nach erfolgreicher Russ-Abnahme.

- [ ] WordPress samt Zertifikatsrestlaufzeit nochmals über gezielte lokale Auflösung prüfen. Private hosts-Zuordnung und exakte ursprüngliche Web-DNS-Werte für den Rückweg bereithalten. Beide alten/neuen App-Profile und Releases dokumentieren.
- [ ] Unter globaler Sperre das geprüfte Stuttgart-Image mit `APP_HOST=stuttgart-live.de`, passenden Hosts, aktiver kanonischer Weiterleitung und ohne globalen Produktions-`noindex` bereitstellen. Neue Hauptdomain vor DNS-Wechsel mit `curl --resolve` prüfen.
- [ ] In der tatsächlich aktiven Host-Europe-Zone ausschließlich Apex A auf `46.225.224.194`, alten Web-AAAA und die `www`-Webzuordnung anpassen. Vollständigen Nicht-Web-DNS-Abgleich bestehen lassen. Domain-/Mail-Assistenten und globale Zonenoptionen nicht verwenden.
- [ ] DNS autoritativ und über unabhängige Resolver prüfen. Für die Abnahme lokale hosts-Overrides entfernen. Startseite, Eventdetail, Suche/Filter, Blog/Altpfade, Medien, Backend, Newsletter-Bestätigung/Abmeldung sowie Meta-/OAuth-Callbacks prüfen. Reale Integrationsaktionen nur an ausdrücklich vereinbarte Testziele.
- [ ] Hauptdomain und `www` mit Pfad/Query, Assets und Medien auf korrektes HTTPS/Redirect-Verhalten prüfen; Canonical, Open Graph, strukturierte Daten und Sitemap müssen die endgültige Domain verwenden. Staging bleibt separat passwortgeschützt und nicht indexierbar.
- [ ] Nach propagiertem DNS automatische Kamal-Zertifikate übernehmen und prüfen. Unverändertes Microsoft-365-DNS und den wiederholten vereinbarten Postfach-Test nachweisen. Zeitpunkt der erfolgreichen Stuttgart-Abnahme als Beginn des mindestens 72-stündigen Rückfallfensters dokumentieren.

## Task 13: Beobachtungsfenster abschließen und WordPress-Abschaltung veranlassen

**Files/Orte:** Betriebsprotokoll, beide READMEs, bisheriger Betreiberkontakt; bestehendes WordPress-Hosting unverändert bis zum Abschluss.

**Interfaces:** Verwendet die Abnahmezeit aus Task 12 und liefert das Abschlussprotokoll mit beendeter Beobachtung, dokumentierter Zertifikatserneuerung und dem Auftrag beziehungsweise der noch offenen Betreiberabhängigkeit für WordPress.

- [ ] Während mindestens 72 Stunden nach erfolgreicher Stuttgart-Abnahme Erreichbarkeit, Sentry/Logs, Ressourcen, Medien, Mailfunktion, Zertifikate und 404-Aufkommen beobachten. Bei produktiven Fehlern zuerst Sentry-MCP und `sentry-fix-issues` verwenden, Hinweise gegen den Code prüfen und über den neuen Freigabeweg korrigieren.
- [ ] Rückfallrelevante Fehler vor Abschluss lösen. Keine Betreiberabschaltung beauftragen, solange der Rückweg noch gebraucht wird. Die Erreichbarkeit des alten Hostings hängt weiterhin vom bisherigen Betreiber ab.
- [ ] Nach erfolgreicher Beobachtung ausschließlich zuvor abgesenkte Web-TTLs auf normale Werte zurückstellen und erneut Nicht-Web-DNS vergleichen. Eigene nicht mehr benötigte ACME-Werte gezielt entfernen; die automatische Zertifikatserneuerung muss übernommen haben.
- [ ] Nach Nutzerkorrektur dürfen alte `schopp3r.de`-Hosts entfallen. Noch benötigte Newsletter-/Medien-/sonstige Links vorab erfassen und den möglichen Ausfall dokumentieren; für den WordPress-Rückweg sind sie nicht erforderlich. Sie werden nicht als Staging verwendet.
- [ ] WordPress-Abschaltung beim ermittelten Betreiber veranlassen. Falls weiterhin kein Kontakt besteht, diesen Abschluss als externe Abhängigkeit dokumentieren; Hosting-/Mailverträge nicht blind kündigen.
- [ ] Lokale hosts-Einträge entfernen und READMEs/Runbook mit tatsächlichen Betriebswerten, Veröffentlichungsweg, manuellem Refresh und Zuständigkeiten abschließen. Die spätere Weiterleitung von `www.michaelrussgmbh.de` wird getrennt geplant.

## Rückfallanweisung bei einem kritischen Fehler

1. Weitere Umschaltungen stoppen, gemeinsame Sperre nutzen und die bereits funktionierende andere App erhalten. Fehlerzustand und Zeitpunkt dokumentieren.
2. Zuerst die betroffene App mit dem zuvor protokollierten Release zurückrollen: `mise exec -- bin/kamal rollback <vorherige-version> -d hetzner`. Zusätzlich das gesicherte Laufzeitprofil einschließlich Hostlisten, Redirects, Indexierung und TLS wiederherstellen und den Digest prüfen; ein Container-Rollback allein reicht nicht.
3. Falls öffentlicher Rückfall nötig ist, nur die selbst geänderten Web-Einträge auf die unmittelbar vorher gesicherten Werte zurückstellen. Bei Stuttgart führt das zurück zum bestehenden WordPress-Hosting. Bei Russ die alte Weiterleitung nur wiederherstellen, wenn dadurch keine Nicht-Web-Einträge verändert werden. Keinen vollständigen Zonenimport ausführen.
4. Hetzner während auslaufender DNS-Caches weiter bedienen; DNS-Rückänderung und vorhandene 301-Caches wirken zeitversetzt. WordPress enthält keine seitdem neu in Rails bearbeiteten Inhalte.
5. Rails-Datenbanken und Medien nicht zurücksetzen oder nach WordPress übertragen. Vorher-/Nachher-DNS-Abgleich und Microsoft-365-Test erneut durchführen. Neue Umschaltung erst nach geklärter Ursache und erneuten erfolgreichen Prüfungen.

## Abdeckung und Planprüfung

| Spezifikationsbereich | Nachweis im Plan |
| --- | --- |
| Domains, `www`, Altlinks und Indexierung | Tasks 4, 8, 10–12 |
| Gleiche Betriebsart und getrennte Ressourcen | Tasks 2, 5, 9 |
| Russ liest passende Stuttgart-Umgebung | Tasks 2, 5, 6, 9 |
| Bereinigung, manueller Refresh, sichere Fehlerzustände | Tasks 3, 6, 9 |
| Getrennte Credentials und externe Schutzregeln | Tasks 2, 3, 6 |
| CI → Staging → manuell dasselbe Image | Tasks 7, 9 |
| Gemeinsamer Host, Sperren und Kapazität | Tasks 5, 7, 9, 13 |
| HTTPS vor Umschaltung und automatische Erneuerung | Tasks 4, 10–12 |
| Unverändertes Nicht-Web-DNS und Microsoft 365 | Tasks 1, 8, 10–13 und Rückfallanweisung |
| WordPress/hosts, 72 Stunden und externe Abschaltung | Tasks 1, 12, 13 und Rückfallanweisung |
| README und verbindliche Projektprüfungen | Global Constraints, Tasks 8, 9, 13 |

Vor Übergabe wurden Spezifikationsabdeckung, Schrittgrenzen, benannte Schnittstellen, die fünf Review-Schwerpunkte und der Umfang geprüft. Die Checkboxes sind Ausführungsschritte und bleiben bis zur tatsächlichen Durchführung offen. Private Laufparameter wie Termin, DNS-Exports und konkrete Release-IDs werden beim jeweiligen Bestands-/Freigabeschritt erfasst und nicht als erfundene Werte vorgegeben.

Technische Grundlagen: [Kamal-Ziele und Konfiguration](https://kamal-deploy.org/docs/configuration/overview/), [Kamal-Proxy und Zertifikate](https://kamal-deploy.org/docs/configuration/proxy/), [Rails-Credentials-Konfiguration](https://guides.rubyonrails.org/configuring.html#config-credentials-content-path), [GitHub-Workflow-Ereignisse](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows). Die Unterstützung von `SOLID_QUEUE_SKIP_RECURRING` und die versionsgebundenen Kamal-Flags wurden zusätzlich am lokal installierten Gem-Code geprüft.
