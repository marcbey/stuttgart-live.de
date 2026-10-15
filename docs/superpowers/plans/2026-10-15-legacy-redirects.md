# Redirect-Service Implementation Plan

**Goal:** Alte Inhalts- und Datei-URLs nach echten 404 auf äquivalente neue Ziele umleiten und im bestehenden Backend verwalten.
**Architecture:** Rails-Rack-Middleware, persistierte LegacyRedirect-Einträge, lokale Matcher, vorbereiteter Sitemap-/HTML-Import und bestehende Backend-Inbox.
**Tech Stack:** Ruby 4.0.2, Rails 8.1, PostgreSQL pg_trgm, Solid Cache, Turbo/Stimulus.
**Spec:** docs/superpowers/specs/2026-10-15-legacy-redirects-design.md

## Global Constraints
- Ruby-Kommandos ausschließlich über mise exec --; geänderte Ruby-Dateien mit RuboCop prüfen.
- Nur echte öffentliche GET-/HEAD-404 auflösen; kein Laufzeit-Webzugriff.
- Manuelle Entscheidungen und deaktivierte Einträge nicht automatisch überschreiben.
- Backend-Design und -Assets des Bereichs Seiten übernehmen.
- Bestehende unversionierte Domainumzugs-Dokumente im ursprünglichen Checkout erhalten.

## Review Focus
- Eine neu veröffentlichte Seite muss alte negative Ergebnisse invalidieren.
- Datei-Zuordnungen dürfen keine geschützten Anhänge offenlegen.
- Eine falsch positive Künstler-/Reihen-Zuordnung darf keine irrelevante 301 erzeugen.
- Fehlerbehandlung darf technische Fehler nicht als dauerhafte 404 speichern.
- Parallele Erstaufrufe und erneuter Import dürfen manuelle Entscheidungen nicht überschreiben.

### Task 1: Persistenz, Ziele und Middleware
Migration und LegacyRedirect-Modell, sichere SourceKey-Normalisierung, Target-Validierung und 404-Middleware. Tests zuerst für gültige/ungültige Ziele, Öffentlichkeit, Pfade und echte 404. Resolver-Schnittstelle für Task 2 vorsehen.

### Task 2: Lokale Auflösung und Cache
Provider- und Inhalts-Matcher, Trigrammähnlichkeit 0,90/0,10, Reihenersatz, Cache-Invalidierung, bestehende Blog-Zuordnungen und öffentliche Integration. Testfälle aus Spec vor Implementierung schreiben; wiederholte Aufrufe dürfen nicht erneut matchen.

### Task 3: Inventarisierung und Betriebswerkzeuge
Fortsetzbarer Sitemap-/HTML-/Datei-Import, sichere begrenzte Netzabrufe, Provider-/Termindatenextraktion, Datei-Prüfsummen, Prüfbericht, Benchmark und README. Netzwerk in Tests durch Fixture-Transport ersetzen.

### Task 4: Backend-Inbox
Admin-Controller, Routen, Navigation und Views nach Seiten-Vorlage. Filter, Pagination, Turbo-Auswahl, Validierung und manuelle Entscheidungen testen; Browser-Abnahme für Desktop und schmale Ansicht.

### Task 5: Integration und Abschluss
Gezielte Tests und RuboCop, vollständiges bin/ci, unabhängige Codeprüfung, Browservergleich, Prüfbericht-/Benchmark-Smoke-Test und verbleibende Betriebsgrenzen dokumentieren.
