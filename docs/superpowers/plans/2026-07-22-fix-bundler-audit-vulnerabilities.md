# Bundler-Audit-Sicherheitsupdates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den fehlgeschlagenen GitHub-Actions-Job 88837305764 beheben, indem die vier von Bundler Audit gemeldeten verwundbaren Gem-Auflösungen aktualisiert und die dadurch wieder erreichten datumsabhängigen Rails-Tests stabilisiert werden.

**Architecture:** Die Anwendung benötigt keine Produktionscode-Änderung. `Gemfile.lock` wird gezielt über Bundler neu aufgelöst; der bereits fehlschlagende Bundler-Audit-Lauf dient als Regressionstest. Drei Tests, deren Juli-Fixtures inzwischen vor `Date.current` liegen, erhalten explizite Zeitvorgaben, bevor `bin/ci` den vollständigen Rails-Stack validiert.

**Tech Stack:** Ruby 4.0.2 über mise, Bundler, bundler-audit, Rails 8.1.3, GitHub Actions

## Global Constraints

- Alle Ruby-, Bundler- und RubyGems-Befehle laufen über `mise exec --`.
- Vor einem möglichen Push müssen `origin/main` erneut gefetcht, der Branch per Fast-Forward oder Rebase aktualisiert und anschließend `mise exec -- bin/ci` erneut erfolgreich ausgeführt werden.
- `README.md` bleibt unverändert, weil weder Nutzung, Betrieb, Setup, Architektur, Abhängigkeitshandhabung noch Troubleshooting geändert werden.
- Es werden keine Advisories ignoriert; jede gemeldete Abhängigkeit wird auf eine reparierte Version aktualisiert.

---

### Task 1: Verwundbare transitive Gems gezielt aktualisieren

**Files:**
- Modify: `Gemfile.lock`
- Verify unchanged: `Gemfile`
- Verify unchanged: `README.md`

**Interfaces:**
- Consumes: die bestehenden Constraints von Rails 8.1.3, RuboCop 1.85.0 und Action Cable 8.1.3
- Produces: ein Lockfile mit `loofah 2.25.2`, `mcp 0.25.0`, `rails-html-sanitizer 1.7.1` und `websocket-driver 0.8.2`

- [x] **Step 1: Den lokalen Branch auf den fehlgeschlagenen aktuellen `main`-Stand bringen**

```sh
git fetch origin main
git merge --ff-only origin/main
```

Expected: `main` zeigt auf mindestens `b6435453e9300acbd764242bebf2c58703116645`; der Fast-Forward erzeugt keine Konflikte.

- [x] **Step 1a: Die vom Fast-Forward neu gelockten Gems installieren**

```sh
mise exec -- bundle install
```

Expected: Bundler installiert das bestehende Lockfile unverändert, sodass der Audit-Befehl die Advisory-Prüfung erreicht.

- [x] **Step 2: Den bestehenden Audit-Fehler als RED erneut bestätigen**

```sh
mise exec -- bundle exec bundler-audit check --update
```

Expected: Exit 1 mit Advisories für `loofah 2.25.1`, `mcp 0.10.0`, `rails-html-sanitizer 1.7.0` und `websocket-driver 0.8.1`.

- [x] **Step 3: Nur die betroffenen Lockfile-Auflösungen aktualisieren**

```sh
mise exec -- bundle lock --update loofah mcp rails-html-sanitizer websocket-driver
```

Expected lockfile excerpt:

```text
    loofah (2.25.2)
    mcp (0.25.0)
      json_schemer (>= 2.4)
    rails-html-sanitizer (1.7.1)
      loofah (~> 2.25, >= 2.25.2)
    websocket-driver (0.8.2)
```

Bundler ersetzt dabei die bisherige `json-schema`-Auflösung von `mcp` durch `json_schemer` und dessen transitive Abhängigkeiten `hana` und `simpleidn`.

- [x] **Step 3a: Die aktualisierten Lockfile-Versionen installieren**

```sh
mise exec -- bundle install
```

Expected: Die neu gelockten Gems werden installiert; `Gemfile.lock` bleibt dabei unverändert.

- [x] **Step 4: Den Audit-Lauf als GREEN bestätigen**

```sh
mise exec -- bundle exec bundler-audit check --update
```

Expected: Exit 0, `No vulnerabilities found`.

- [x] **Step 5: Den vollständigen Projekt-CI-Lauf ausführen**

```sh
mise exec -- bin/ci
```

Expected: RuboCop, Brakeman, Bundler Audit und Rails-Tests laufen ohne Fehler durch.

- [x] **Step 6: Den Änderungsumfang prüfen**

```sh
git diff --check
git diff -- Gemfile Gemfile.lock README.md
```

Expected: keine Whitespace-Fehler; nur die beschriebenen Sicherheitsupdates und ihre notwendigen transitiven Lockfile-Abhängigkeiten ändern sich. `Gemfile` und `README.md` bleiben unverändert.

## Self-Review

- Der Plan deckt alle zehn im Job gemeldeten Advisories ab: drei für Loofah, fünf für MCP, eines für Rails HTML Sanitizer und eines für WebSocket Driver.
- Es gibt keine Ignore-Konfiguration und keine fachfremden Versionsupdates.
- Alle Ruby-/Bundler-Befehle verwenden die in `mise.toml` gepinnte Ruby-Version.
- Der bestehende Audit-Fehler wird vor der Lockfile-Änderung reproduziert und danach sowohl gezielt als auch über `bin/ci` verifiziert.

---

### Task 2: Datumsabhängige Rails-Tests stabilisieren

**Files:**
- Modify: `test/controllers/backend/events_controller_test.rb`
- Modify: `test/helpers/public/events_helper_test.rb`

**Interfaces:**
- Consumes: `Backend::EventsControllerTest::FIXTURE_NOW` und Rails `travel_to`
- Produces: deterministische Tests unabhängig vom realen Kalenderdatum

- [x] **Step 1: Die bereits fehlgeschlagenen Tests als RED dokumentieren**

```sh
mise exec -- bin/rails test test/controllers/backend/events_controller_test.rb:2641 test/controllers/backend/events_controller_test.rb:2741 test/helpers/public/events_helper_test.rb:88
```

Expected: drei Fehler, weil die Fixtures vom 10. und 12. Juli 2026 am 22. Juli 2026 aus dem Inbox-Filter fallen beziehungsweise als vergangen markiert werden.

- [x] **Step 2: Die Controller-Tests am etablierten Fixture-Zeitpunkt ausführen**

```ruby
travel_to FIXTURE_NOW do
  # bestehender Request und bestehende Assertions
end
```

Die Blöcke werden ausschließlich um `turbo publish keeps active needs_review filter and refreshes inbox` und `index shows event series badge for grouped events` gelegt.

- [x] **Step 3: Das Helper-Testevent explizit als zukünftig markieren**

```ruby
event.start_at = 1.day.from_now
```

Dadurch testet der Fall nur noch das geplante Veröffentlichungs-Badge und hängt nicht vom absoluten Fixture-Datum ab.

- [x] **Step 4: Die drei Tests als GREEN bestätigen**

```sh
mise exec -- bin/rails test test/controllers/backend/events_controller_test.rb:2641 test/controllers/backend/events_controller_test.rb:2743 test/helpers/public/events_helper_test.rb:88
```

Expected: drei Läufe, null Fehler.

- [x] **Step 5: RuboCop für die geänderten Ruby-Dateien ausführen**

```sh
mise exec -- bundle exec rubocop test/controllers/backend/events_controller_test.rb test/helpers/public/events_helper_test.rb
```

Expected: keine Verstöße.
