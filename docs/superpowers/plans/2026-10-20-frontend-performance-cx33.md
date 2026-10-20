# Frontend-Performance auf CX33 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die belegten Ladeengpässe auf dem vorhandenen CX33 beheben und Wirkung sowie Betrieb messbar machen; vorerst kein Serverwechsel.

**Architecture:** Bestehende Rails-/Stimulus-Oberflächen gezielt optimieren. Unnötige Requests und Datenmaterialisierung vermeiden, sichtbare Ressourcen früh laden, Medienarbeit in begrenzte Hintergrundjobs verlagern. Öffentliche HTML-Seiten mit Auth-/CSRF-Anteilen nicht vollständig gemeinsam cachen; Web, Jobs und PostgreSQL bleiben auf dem CX33.

**Tech Stack:** Ruby 4.0.2 über mise, Rails 8.1, PostgreSQL 16, Solid Cache/Queue, Stimulus/Turbo, esbuild/Tailwind, nginx/Puma/Kamal.

**Spec:** Vom Nutzer zur Umsetzung freigegebener Entscheidungsbericht: `/Users/marc/Projects/stuttgart-live.de/output/playwright/performance-2026-10-20/decision-report.html`; Messdaten und konkreter Codeaudit im gleichen Verzeichnis. Nutzerergänzung: „Optimiere auf CX33 wo nötig — kein Umzug auf CCX23 vorerst.“ Dieser Plan konkretisiert die bereits freigegebenen Empfehlungen.

## Global Constraints

- Arbeiten im isolierten Worktree `/Users/marc/.codex/worktrees/frontend-performance-cx33/stuttgart-live.de`, Branch `codex/frontend-performance-cx33`; fremde Änderungen im ursprünglichen Checkout nicht übernehmen oder verändern.
- Ruby-/Bundler-/Rails-Kommandos ausschließlich `mise exec -- ...`; geänderte Rubydateien vor Abschluss mit RuboCop prüfen.
- Isolierte Testdatenbank: `DATABASE_URL=postgresql:///stuttgart_live_de_performance_test`. Während paralleler Verifikation keine DB-Präparation oder Seed-Replants starten.
- `bin/ci` vollständig vor Abschluss und vor jedem Push; vor Push Remote holen und Branch aktualisieren; nach Aktualisierung erneut CI. Keine geheimen Werte ausgeben, keine Umgebungsdumps.
- Frontend-/Backend-Assets getrennt halten; Fonts lokal; deutsche Texte mit Umlauten/ß.
- Kein CCX-/Rootserverkauf, kein Architekturwechsel zu getrennten Produktionsdatenbanken/Uploads. Publikationszeit, Zeitzone, Authentifizierung, Filter, Ticketstatus, Serien und Russ-Kopplung erhalten.
- TDD für relevante Verhaltensänderungen; HTML-/Browser-/SQL-Verträge prüfen, keine Tests bloßer Quelltextzeilen. Vollsuite einmal je abschließender Änderungseinheit, gezielte Tests während Iteration; zentrale CI am Ende.
- Jeder Task enthält gezielte README-Ergänzungen zum veränderten Verhalten; finale Betriebsanleitung wird in Task 8 zusammengeführt.
- Code und Konfiguration werden vor Produktionsänderungen vollständig prüfbar gemacht. Runtimeanpassungen nur mit gemessenen Ressourcen, Rückfallmöglichkeit und dokumentiertem Rollout.
- Aktuelles AGENTS.md/INFRA.md ist für Veröffentlichung verbindlich: PR → Main-CI → Deploy Staging → gültiger Nachweis → menschliche GitHub-Environment-Freigabe durch marcbey oder kasch0. Keine direkten Kamal-Deploys oder Image-Neubauten als Ersatz; aktuelle Betriebsanleitung vor Host-Eingriffen lesen.

## Review Focus

- Direkte Navigation, Turbo-Rücknavigation und erste Interaktion müssen mit leerem Cache und ohne Einwilligung funktionieren; verspätete Initialisierung darf Klicks nicht verlieren.
- Publikationsgrenzen, Mitternacht, Preis-/Bildänderungen und angemeldete Redakteure dürfen keine falschen gemeinsamen Caches erhalten.
- Resize zwischen 412/768/1350/1536 px, reduzierte Bewegung und Data-Saver dürfen kein verborgenes Video laden oder die Bedienung beschädigen.
- Importierte Bilder mit ungültigen URLs, großen Datenmengen, Fehlerantworten und geänderten Quellen dürfen Webrequests nicht blockieren oder private Netzwerke abrufen.
- Proxy-/Pumastatistik und Browsermetriken dürfen keine Secrets, Suchtexte, Personen-IDs oder vollständigen Querystrings erfassen; verweigerter/widerrufener Consent muss berücksichtigt sein.

---

### Task 0: Zeitunabhängige Ticket-Testdaten als grüne Ausgangsbasis

**Files:** `test/models/event_test.rb`; keine Produktionsdatei.

**Interfaces:** Bestehende fachliche Tests und ihre Assertions bleiben erhalten. Die drei abgelaufenen Termine waren nur im alten lokalen main vorhanden; aktuelles origin/main enthält bereits korrekte relative Zukunftstermine und erfüllt diesen Task. Keine zusätzliche Änderung darüberlegen.

- [ ] RED bereits belegt: `output/performance/baseline-ci.log` enthält Fehler in `public_ticket_offer falls back to manual when no imported offer exists`, `public_sold_out? follows the manual ticket status offer` und `manual ticket offer overrides canceled imported offer`; erwartetes manuelles Angebot, tatsächlich nil wegen vergangenem Eventdatum.
- [ ] Ausschließlich die drei betreffenden `start_at`-Werte auf eine Woche nach aktueller Testzeit, lokale Uhrzeit20:00, ändern. Keine Ticketlogik oder Assertions abschwächen; bestehende explizite Tests für vergangene Events erhalten.
- [ ] GREEN: Eventmodelltests, dann `mise exec -- env DATABASE_URL=postgresql:///stuttgart_live_de_performance_test QUEUE_DATABASE_URL=postgresql:///stuttgart_live_de_performance_queue CABLE_DATABASE_URL=postgresql:///stuttgart_live_de_performance_cable bin/ci`; keine anderen Tests gleichzeitig. RuboCop auf Testdatei; Commit `test(events): keep ticket availability fixtures in the future`.

### Task 1: Lokale Browserfonts verkleinern

**Files:** Modify `app/helpers/application_helper.rb`, `app/views/layouts/application.html.erb`, `test/helpers/application_helper_test.rb`, `test/helpers/local_font_stylesheet_test.rb`; create `app/assets/fonts/oswald-300.woff2`, `app/assets/fonts/oswald-400.woff2`; README.

**Interfaces:** `LOCAL_FONT_FACES` und `local_font_face_stylesheet(frontend:)` behalten ihre bestehende Schnittstelle. Serverseitige TTF-Dateien für Pango/Fontconfig bleiben verfügbar.

- [ ] RED: Integrations-/Helpertest zeigt, dass öffentliche und Backend-Font-Faces für Gewicht 300/400 lokale WOFF2 statt TTF referenzieren. Assertions auf gerendertes CSS und gültige Assets; bestehende lokale Preloads dürfen keinen TTF-Request auslösen.
- [ ] Vorhandene TTFs mit vorhandenen Fonttools verlustfrei in WOFF2 konvertieren; Zeichenabdeckung und Metriken erhalten. Kein externes Font-CDN und keine neue Fontfamilie. Nicht auf ASCII beschränken.
- [ ] Font-Faces/Preloads auf die tatsächlich gerenderten Formate umstellen; keine unnötigen zusätzlichen Gewichte vorladen. Fontfallbackänderungen nur bei belegter metrischer Verbesserung.
- [ ] GREEN: betroffene Tests, Glyphen-/Metadatenprüfung und Bytes vorher/nachher dokumentieren; gesamte Rails-Suite einmal und RuboCop auf geänderte Rubydateien.
- [ ] README lokal erläutern, warum Browser WOFF2 und Renderjobs weiterhin TTF verwenden; eigene Dateien committen (`perf(fonts): ...`).

### Task 2: LCP-Bilder, Slider und verstecktes Video

**Files:** `app/views/public/events/_design_preview_card.html.erb`, `_design_preview_banner_card.html.erb`, `_design_preview_header.html.erb`, `_homepage_highlight_video.html.erb`, `design_preview.html.erb`, `lane.html.erb`, `search.html.erb`, `design_preview_detail.html.erb`; `app/views/public/news/_card.html.erb`, `index.html.erb`; passende aufrufende Partials; `app/javascript/controllers/design_preview_feature_slider_controller.js`, `video_sound_controller.js` oder eigener kleiner Controller; `highlights_slider_controller.js` nur falls ein nachgewiesener moderner Fehlanschluss das erfordert; `public_index.js` nur bei Registrierung; gezielte Integration-/Browsertests; README.

**Interfaces:** Karten erhalten optional `image_priority: false` und gegebenenfalls `image_loading:`. Höchstens der sichtbare wahrscheinliche LCP-Kandidat erhält `fetchpriority=high`; tiefe Karten bleiben lazy. Vorhandene Kartenaufrufe behalten ihre Standardsemantik.

- [ ] RED: repräsentative Lane/Suche/News rendern erstes sichtbares Bild eager/high und spätere Karten lazy. Direkte Unterseiten enthalten keinen unbedingten Logo-Turbo-Preload. Detailbild bleibt eager, mit passender Priorität.
- [ ] Browser-RED: Feature-Slider wechselt vor bewusster Interaktion nicht automatisch; Pfeile/Swipe funktionieren. Erster Slide darf bereits richtig priorisiert sein und nicht durch einen späteren lazy Slide als LCP verdrängt werden.
- [ ] Browser-RED: bei 412/1350 px wird keine MP4-Quelle angefordert; sichtbare Kachel ab 1536 px kann laden/abspielen. Kein `src`/`source[src]` vor passenden Media-/Sichtbarkeitsbedingungen, `preload=none` allein genügt nicht. Data-Saver/Reduced-Motion beachten; Tonbutton und Resize funktionieren.
- [ ] Bereits produktiv korrigierte Sliderinitialisierung erhalten: moderner Highlightbereich nutzt nur `homepage-lane`, ältere Slider besitzen ihren eigenen `track`-Target. Keine alte Controllerexception beim Optimieren wieder einführen.
- [ ] Genau diese bestehenden Verhaltenspfade korrigieren; keine pauschale eager-Priorität aller Karten und kein visueller Umbau. Breiten/Höhen für Newsbild ergänzen, ohne bestehendes Seitenverhältnis/Crop zu ändern.
- [ ] GREEN: gezielte Rails-/Browsertests einschließlich erster Interaktion, Resize und Turbo-Navigation; Fullsuite/RuboCop; README-Verhalten dokumentieren und committen.

### Task 3: Unnötige Chrome-/Suchabfragen und N+1 beseitigen

**Files:** `app/controllers/public/events_controller.rb`, `news_controller.rb`, `pages_controller.rb`; `app/helpers/application_helper.rb`; `app/services/public/events/search/overlay_builder.rb` nur falls erforderlich; `app/services/public/news/related_genre_resolver.rb`; `app/models/event.rb` nur für tatsächlich preloadfreundlichen Zugriff; Toolbar-/Overlaypartials und `public_search_controller.js`; Tests für diese Controller/Services, zusätzlich schlanker Integrationstest für SQL-Verhalten; README.

**Interfaces:** Vorhandener `/events/search_overlay`-Endpunkt bleibt die Quelle für Overlaydaten. Gemeinsame Navigation bezieht Labels/URLs aus der bestehenden LaneDirectory, ohne vollständige Event-Lanes zu bauen. Öffnen der Suche lädt fehlende Idle-Daten genau bei Bedarf; Query/Datumfilter und Backendvorschau bleiben korrekt.

- [ ] RED: FAQ und Newsnavigation zeigen dieselben Genres/Links, führen aber keine unsichtbaren Event-Lane-/Idle-Suchselektionen aus. Detail-/Lane-/Suchseiten laden nur sichtbare Sidebar-/Seiteninhalte. SQL über Notifications erfassen und verbotene unnötige Event-/Attachmentabfragen identifizieren statt fragile Gesamtzahl festzuschreiben.
- [ ] RED: erster Suchfokus lädt Idle-Vorschläge, Eingaben weiterhin mit vorhandenem Debounce/Abort; zwei Toolbars duplizieren Requests nicht unnötig. Authed/Draft/Scheduled/Datumfälle aus bestehenden Tests erhalten.
- [ ] Gezielt Associations für tatsächlich gerenderte Karten preloaden; `primary_genre` muss geladene Genres nutzen. Attachment-N+1 aus Sentry am realen konsumierenden Pfad nachweisen und beheben, ohne pauschal alle Blobassoziationen zu laden.
- [ ] News-Genrezuordnung nur mit ID/Künstler/Titel/Genres ausführen; breite Medien-/Offer-Includes und unnötiges DISTINCT vermeiden, identische Ergebnislogik einschließlich mehrdeutiger Artikel erhalten. Nicht benötigte Highlightsidebar nur einmal laden.
- [ ] GREEN: fachliche Controller-/Servicetests und Querytrace cold/warm, Bullet, Fullsuite/RuboCop. SQL-/Objekt-/Zeitenvergleich dokumentieren, README und Commit.

### Task 4: Wirksame moderne Fragmentcaches

**Files:** `app/helpers/public/events_helper.rb`, tatsächlich verwendete moderne Karten-/Lane-/Bannerpartials und deren rendernde Views, bestehende Cachetests beziehungsweise neue Integrationtests; nur belegte zusätzliche Preloads; README.

**Interfaces:** Bestehendes Solid Cache bleibt. Anonyme gemeinsame Karten-/Lane-Fragmente dürfen gecacht werden; vollständiges Auth-/CSRF-HTML nicht. Bestehende `public_events_section_cache_key`-/Renderkomponenten möglichst wiederverwenden und auf bereits geladene Daten beschränken.

- [ ] RED: identische anonyme Anfrage nutzt ein warmes Fragment; nach Event-/Offer-/Media-/Genre-/AppSettingänderung ist sichtbarer Inhalt frisch. Auth-Admincontrols erscheinen nie aus anonymem Cache; Filter/Datum/Serienanzahl/Varianten/Linkparameter haben getrennte Keys.
- [ ] Cache an tatsächlich gerenderten modernen Pfaden ergänzen. Vor dem Lookup keine zusätzlichen Associationqueries oder teuren Schlüsseltraversierungen; kein AR-Objektsnapshot und kein Rediswechsel. Publikations-/Tagesgrenzen durch fachliche Selektion und begrenzte Zeitabhängigkeit berücksichtigen.
- [ ] Falls ein Kandidat schon beim Keybau mehr Arbeit als beim Rendern erzeugt, zuerst diesen Pfad vereinfachen oder den unwirksamen Cache verwerfen und mit Messbeleg dokumentieren; keine Maßnahme ohne Nutzen erhalten.
- [ ] GREEN: Invalidierungs-/Auth-/Zeit-/Hit-Miss-Tests, realer warm/kalt SQL-/Rendervergleich, Fullsuite/RuboCop; README-Invalidierung/Diagnose und Commit.

### Task 5: Responsive Bilder und asynchrone Varianten

**Files:** `app/helpers/application_helper.rb`, `app/models/event_image.rb`, `import_event_image.rb`; vorhandene Importdownload-/Bildservices und `app/jobs/event_images/`; passende Modell-/Service-/Integrationtests, Backfill-Raketask; Karten-`sizes` nach Task 2; README.

**Interfaces:** Bestehende Quellen/Crops/Rechteinformationen erhalten. Lokale optimierte Repräsentationen sind nach erfolgreicher Verarbeitung bevorzugt; solange sie fehlen, bleibt eine funktionsfähige vorhandene Quelle verfügbar. Kein synchroner neuer Providerdownload im HTML-Pfad.

- [ ] RED: `sizes` entsprechen realem Slot, Srcset-Deskriptoren tatsächlicher intrinsischer Breite auch bei Hochformaten. Unterschiedliche kleine Related-/Listen-/Hero-Slots dürfen nicht alle dieselbe große Quelle wählen.
- [ ] RED: neue/ersetzte lokale Eventbilder erzeugen öffentliche Varianten im Hintergrund; HTML-Anfragen benötigen keine neue synchrone Transformation. Fehlende/beschädigte Bilder funktionieren mit bestehendem Fallback.
- [ ] Bestehende sichere Downloadlogik für Importbilder wiederverwenden; asynchron lokal optimieren, Quelleänderung invalidiert alten Output. Tests für private/ungültige URL, Größen-/Zeitlimits, Fehler/Retry und unveränderte Quelle. Keine neue offene Proxyroute.
- [ ] Begrenzte Jobparallelität (höchstens ein aktiver öffentlicher Bildbackfill/-transformationsjob je Host) und expliziter Dry-run-/Limit-Backfill für veröffentlichte künftige Events. Keine ungeprüfte Massendownloadaktion auf Produktion.
- [ ] GREEN: Transformation-/Import-/Fallbacktests, tatsächliche Pixel-/Byteprüfung, Fullsuite/RuboCop; README mit schrittweisem Backfill und Lastkontrolle, Commit.

### Task 6: CX33-Queue, Proxy und Worker messbar entlasten

**Files:** `config/nginx.conf.template`, `config/puma.rb`, `config/deploy.hetzner.yml`, `config/deploy.hetzner.shared.yml`, `config/database.yml` nur bei begründetem Poolbedarf; kleine Rack-/Telemetryklasse und deren Konfiguration; `test/lib/nginx_config_test.rb`, `hetzner_deploy_config_test.rb`, neue Runtime-/Middlewaretests; `public/robots.txt` beziehungsweise bestehende Robotsquelle; README.

**Interfaces:** Proxy nginx→Puma erhält einen vom Proxy überschriebenen Requeststart-Zeitstempel. Metriken: Queuezeit, Appzeit, Status/Route/Release; keine vertraulichen Querystrings. Pumastats über internen Unixsocket, kein öffentlicher Steuerport.

- [ ] RED: Queuezeitberechnung toleriert fehlende, kaputte, zukünftige und überlange Headers; eingehende Spoofwerte werden am Proxy ersetzt. Pool-/Pumaeinblicke lösen selbst keine Datenbankabfrage aus und erzeugen keine Secrets in Logs.
- [ ] Auf echtem nginx kontrolliert Requests testen: bekannte nicht notwendige Crawlerklassen erhalten begrenztes dynamisches Budget und sauberes 429/Retry-Verhalten; Assets/Medien/Healthchecks und normale Nutzer bleiben verfügbar. Useragent ist Klassifizierung, keine verifizierte Identität. Keine IP-basierte Regel auf ungeprüftem X-Forwarded-For oder pauschaler Sperre wichtiger Suchmaschinen.
- [ ] Logs mit Request-ID, nginx-/Upstreamzeiten und sanitisiertem Pfad ergänzen; Logretention begrenzen und für Vorher/Nachher nutzbar halten. Kooperative Robotsregeln für nicht indexierbare Such-/Overlaypfade prüfen.
- [ ] Aktuellen Domain-/Indexierungsmodus beim Rollout erhalten: `HetznerDeployConfig` und GitHub-Variable `PRODUCTION_DOMAIN_MODE` steuern Legacy/Kanonisch/Redirect/TLS. Produktiv ist `stuttgart-live.de` ohne noindex; keinen Legacy-Default oder Stagingparameter beim Performancedeploy erzwingen. Vorhandene getrennte Stagingkonfiguration und Russ unverändert halten.
- [ ] Vor Workeränderung reale PSS/RSS-/Poolbudgets aller vier Stacks inklusive Rolloutüberlappung berechnen. Zwei→drei Worker ausschließlich im kontrollierten Vergleich; bei zu wenig Reserve bei zwei bleiben und Entscheidung messen. Threads nicht pauschal erhöhen.
- [ ] GREEN: Middleware-/Configverhalten und nginx-Syntaxtest/Integration, volle CI/RuboCop. README beschreibt interne Diagnose, Änderungen, Schwellenvorschläge, Poolbudget und Rückfall auf vorherige Konfiguration; Commit.

### Task 7: Consentabhängige reale Web Vitals

**Files:** kleiner öffentlicher JS-Metrikadapter, `app/javascript/public.js`, `consent_controller.js` nur bei Bedarf; `package.json`, vorhandene Lockdateien; Release-Meta in Layout; JS-/Browsertests und bestehende Consenttests; README.

**Interfaces:** Offizielle `web-vitals`-Bibliothek dynamisch nach Analytics-Einwilligung laden und an vorhandenes GA4 `gtag` anbinden. Keine neue Rails-Collectorroute, kein zusätzliches externes Tracking ohne vorhandene Zustimmung. API-/Versionswahl anhand offizieller aktueller Dokumentation prüfen.

- [ ] RED: ohne Zustimmung kein Import/Report, nach Zustimmung Reports für LCP/INP/CLS/FCP/TTFB, nach Widerruf keine weiteren Reports; race während dynamischem Import berücksichtigen. Fehlendes Analyticsziel/unsupported API darf Funktion nicht beeinträchtigen.
- [ ] Payload auf Metrikname, Zahlenwert/Einheit, zufällige Messungs-ID, Gerätesegment, Route als Muster, Release und Navigationstyp begrenzen. Keine vollständigen URLs, Suchtexte, DOMtexte oder personenbezogenen IDs. BFCache/Turbo-Semantik und Mehrfachreports pro ID korrekt dokumentieren.
- [ ] Messung getrennt von asynchroner Suchantwortlatenz halten. Bestehende Oberflächen-/Consentinitialisierung nicht verdoppeln. Keine Authevents oder Backend-Bundles mit öffentlichem RUM versehen.
- [ ] GREEN: reale Browser-/Consent-/Payloadtests, Bundlegrößenvergleich, JS-Build und Fullsuite soweit Rails/Layout betroffen; README erklärt GA4-Dimensionen, Export/p75 je Gerät/Route, Stichproben, 24h/7d-Frühsignal und vollständiges 28-Tage-Fenster; Commit.

### Task 8: Reproduzierbarer Performancecheck und Betriebsanleitung

**Files:** `script/performance/` mit kleinem Mess-/Auswerteskript, nötige Dev-Abhängigkeit/Lockdateien, Workflow unter `.github/workflows/`, zusammengeführte README-Abschnitte; gezielte Parser-/Budgettests nur für nichttriviale Auswertung.

**Interfaces:** CLI für Produktion und lokalen Vergleich mit Basis-URL, Profil, URLliste und Wiederholungen; JSON/CSV/HTML-Artefakte ohne Secrets. Mobil identische direkte DevTools-Drosselung wie Baseline; Desktop ohne künstliche Drosselung; Browsercache frisch, Servercachezustand explizit.

- [ ] Die vorhandenen funktionierenden Baselineskripte aus dem Audit gezielt wiederverwendbar machen, keine 48 Rohreports versionieren. Kein bloß simulierter LCP, wenn beobachteter Tracewert abweicht.
- [ ] Manueller und ressourcenschonender regelmäßiger öffentlicher Check für Startseite/News/FAQ mit Artefakten; serielle Requests, sinnvolle Timeout-/Fehlerbehandlung und eindeutige Unterscheidung Infrastrukturfehler/Budgetregression. Keine produktiven Schreibaktionen.
- [ ] Gates behandeln LCP/FCP/TTFB/CLS/TBT im Labor getrennt vom echten Feld-INP. Targets: LCP≤2500ms, Feld-INP≤200ms, CLS≤0,1; FCP≤1800ms, TTFB≈800ms als Diagnoseziele. Kein Good-Versprechen allein aus drei Läufen.
- [ ] README menschlich zusammenführen: Architektur bleibt CX33, Diagnose/Pool-/Workerbudget, Botregeln, Bild-/Fontpipeline, Cacheinvalidierung, RUM, CI, Backfill und Rollback. Keine widersprüchlichen alten Betriebswerte stehen lassen.
- [ ] Build-/Parsertests, Workflowsyntax, volle CI und Commit; Baseline-/Nachherartefakte im ignorierten Output ablegen.

### Task 9: Integration, Review und sicherer CX33-Rollout

**Files:** finale Prüfarbeitsartefakte; README nur bei tatsächlichem Rolloutbefund; keine fachfremden Änderungen.

**Interfaces:** Integrierter Branch aus Tasks 1–8; bestehender Kamal-/GitHub-Produktionsworkflow und aktueller CX33. Keine Änderung des Hardwaremodells.

- [ ] Vollständigen Branchdiff und alle Taskberichte gegen freigegebenen Bericht prüfen; unabhängige Gesamtprüfung. Wichtige Befunde beheben und genau den Fix erneut prüfen. Hypothetische CLS-/JS-Probleme nur bei Reproduktion ändern.
- [ ] `mise exec -- ... bin/ci`, RuboCop und Assetbuild mit finalem Stand; HTTP-/Browserprüfung repräsentativer Seiten und Interaktionen auf Port3000, kalte/warme Caches. Ausgangsänderungen im ursprünglichen Checkout weiterhin unberührt.
- [ ] Vor Remoteänderung Zielbranch aktuell holen/aktualisieren; anschließend erneut CI. Konkreten geprüften Stand bereitstellen; erforderliche Veröffentlichung-/Produktionsfreigaben erst am fertigen Ergebnis klären, nicht während Umsetzung erneut um generelle Erlaubnis bitten.
- [ ] Vor tatsächlichem Rollout Backupstatus, Rollout-RAMreserve und Rückfallrelease prüfen. Keine Secrets ausgeben. Kein gleichzeitiger Schreibbetrieb auf neuen Hosts; kein anderer Host vorgesehen. Bildbackfill begrenzt und separat messbar.
- [ ] Nach Rollout dieselbe Produktionsmatrix und Interaktionen wiederholen, Queue-/CPU-/RAM-/Pool-/Fehlerwerte vergleichen. Bei Regression Rückfall statt ungeprüfter Folgetweaks. Ergebnisse und verbleibende Beobachtungszeit transparent berichten; erst dann Zielabschluss prüfen.

### Task 10: Isolierte CI-Datenbank vom Staging-Unterprozesstest trennen

Dieser kleine Setupfix wird nach dem Rebase und vor Task2 ausgeführt; er ist keine Wiederholung von Task0, dessen Datumskorrekturen bereits upstream vorhanden sind.

**Files:** ausschließlich `test/lib/staging_readiness_test.rb`.

**Interfaces:** `DeploymentEnvironment.validate_runtime!` muss geerbte Datenbank-URLs in Staging weiterhin ablehnen. Der gezielte Readiness-Test soll einen gültigen Staging-Prozess ohne Readiness-Marker starten; dafür dürfen seine isolierten lokalen Test-DSNs nicht in den Kindprozess gelangen.

- [ ] RED liegt in `output/performance/rebased-ci.log`: bei `DATABASE_URL=postgresql:///stuttgart_live_de_performance_test` scheitert der Unterprozess bereits an `DATABASE_URL is forbidden in staging`, bevor die zu prüfende fehlende Readiness-Datei erreicht wird. Eine Failure in1725Tests, alle übrigen CI-Stufen grün.
- [ ] Im Test `direct web and worker commands refuse unready stage before credentials or database boot` die an `Open3.capture3` übergebene Umgebung um `nil`-Einträge für geerbte `DATABASE_URL` und alle `*_DATABASE_URL` ergänzen; alle anderen Umgebungs-/Fehlerassertions unverändert. Keine Produktionsdatei verändern und keine Staging-Prüfung abschwächen.
- [ ] GREEN: `mise exec -- env DATABASE_URL=postgresql:///stuttgart_live_de_performance_test QUEUE_DATABASE_URL=postgresql:///stuttgart_live_de_performance_queue CABLE_DATABASE_URL=postgresql:///stuttgart_live_de_performance_cable bin/rails test test/lib/staging_readiness_test.rb test/lib/deployment_environment_test.rb`. Bestehende Ablehnungstests für explizite Datenbank-URLs müssen weiter bestehen.
- [ ] RuboCop nur auf geänderte Testdatei und vollständiges `bin/ci` mit denselben drei isolierten DSNs, ohne `LOCAL_DESIGN_CHECKS=1`. Alle Tests einschließen. Nur Testdatei committen; Bericht mit RED/GREEN/CI und echtem SHA.
