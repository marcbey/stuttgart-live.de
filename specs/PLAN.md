# Projektplan: Relaunch Stuttgart Live

## 1. Zielbild
- Relaunch von `stuttgart-live.de` als performante Rails-Anwendung mit klar getrennten Komponenten:
  1. Import-System (Easyticket, Reservix, Eventim)
  2. Redaktions-Backend (Review, Korrektur, manuelle Eingabe, Publishing)
  3. Oeffentliches Frontend (modernes, responsives Event-Grid + Detailseiten)
- Fokus: hohe Datenqualitaet, schneller redaktioneller Workflow, saubere UX ohne Paging.

## 2. Technischer Rahmen
- Ruby: `4.0.1`
- Ruby on Rails: `8.1.2`
- Frontend-Stack: Hotwire (Turbo + Stimulus), Tailwind CSS
- Datenbank: PostgreSQL `18`
- Jobs/Queue: Active Job + Solid Queue
- Authentifizierung Redaktion: Rails built-in Generator (`rails generate authentication`)
- Deployment: Docker + Kamal
- Infrastruktur: AWS, provisioniert mit Terraform
- Analytics: zunaechst keine Integration


## 3. Architektur (High-Level)
- Monolithische Rails-App mit klaren Modulen:
  - `Importing` (Connectoren, Normalisierung, Upsert, Run-Tracking)
  - `Editorial` (Review, Qualitaetspruefung, Freigabe, manuelle Erfassung)
  - `Public` (Event-Listing, Infinite Scroll, Details)
- Schichten:
  - Models fuer persistente Domainobjekte
  - Service Objects fuer Import-, Merge- und Publishing-Workflows
  - Query Objects fuer performante Listenansichten
  - Presenter/Decorator fuer UI-spezifische Darstellung
- Prinzipien:
  - idempotente Imports
  - source-uebergreifendes Zusammenfuehren gleicher Events
  - nachvollziehbare Aenderungshistorie
  - Bulk-optimierte Redaktion
  - progressive Enhancement mit Turbo/Stimulus

## 4. Komponente A: Import-System

### 4.1 Funktionsumfang
- Wiederkehrender Abruf der APIs/Feeds:
  - Easyticket (XML Dump & JSON API)
  - Reservix (JSON API)
  - Eventim (GZIP XML Feed, Streaming-Parser)
- Normalisierung auf ein kanonisches Source-Event-Schema
- Validierung (Pflichtfelder, URL-Checks, Datum/Zeitzone, Duplikate)
- Idempotentes Upsert in source-nahe Tabellen und Deaktivierung veralteter Datensaetze
- Laufhistorie, Metriken, Fehlerprotokolle

### 4.2 Importer-Konfiguration im Backend
- UI fuer konfigurierbare Parameter:
  - aktiv/inaktiv pro Quelle
  - target cities / location whitelist (pro Quelle)
  - location whitelist default fuer Easyticket:
    - `Stuttgart`
    - `Stuttgart - Bad Cannstatt`
    - `Stuttgart Bad-Cannstatt`
    - `Esslingen am Neckar`
  - Frequenz/Zeitslot
  - provider priority fuer Merge + Ticket-CTA (default: `reservix -> eventim -> easyticket`)
- Tabellenvorschlag:
  - `import_sources`
  - `import_source_configs` (JSONB fuer source-spezifische Parameter)
  - `provider_priorities`
  - `import_runs`
  - `import_run_errors`

### 4.3 Job-Orchestrierung (Solid Queue)
- Recurring Scheduler-Job (taeglich 03:05 Europe/Berlin)
- Pro Quelle ein eigener Run-Job
- Manuelles Triggern einzelner Quellen ueber Backend-UI durch Redakteure/Admins
- Schritte pro Run:
  1. Fetch
  2. Parse
  3. Normalize
  4. Validate
  5. Upsert
  6. Deactivate stale
  7. Persist metrics
  8. Optional: Downstream-Merge-Pipeline anstossen (entkoppelt)
- Retry/Backoff und Fehlerisolation pro Quelle

### 4.4 Datenqualitaet & Auto-Publishing
- `EventCompletenessChecker` vergibt `completeness_score` und Flags (fehlendes Bild, Genre, Ticket-URL etc.)
- Regel:
  - Datensatz komplett (`ready_for_publish`): wird automatisch publisht
  - Datensatz unvollstaendig: landet in `needs_review`

### 4.5 Easyticket Importer v1 (erste Umsetzung)
- Ziel:
  - Zuerst nur Easyticket end-to-end implementieren.
  - Noch kein source-uebergreifendes Merge in diesem Schritt.
- Input/Config:
  - Eventliste via `XMP_DUMP_URL` aus `.env`
  - Event-Details via `EVENT_DETAIL_API` aus `.env`
  - Credentials/URL-Bausteine aus `.env` (z. B. `USER`, `PASS`, `API_KEY`, `PARTNER_SHOP_ID`, `TICKET_LINK_EVENT_BASE_URL`)
  - Backend-konfigurierbare Ortsliste (Whitelist), Default siehe 4.2
- Ablauf:
  1. XML-Dump ueber Connector abrufen.
  2. Eventliste parsen und `event_id` extrahieren.
  3. Events ueber konfigurierbare Ortsliste filtern.
  4. Fuer jedes gefilterte Event Detail-API mit `event_id` aufrufen.
  5. Detail-JSON unveraendert persistieren.
  6. Projektionen fuer Backend/Weiterverarbeitung speichern:
     - Band/Kuenstlername
     - Konzert-Datum als Anzeigeformat (z. B. `17.6.2026`)
     - Venue-String (z. B. `Stuttgart, Im Wizemann`)
  7. Idempotentes Upsert pro Event.
- Ergebnis:
  - Vollstaendige technische Rohdaten (JSON) + wichtige Felder sind in der Easyticket-Importtabelle verfuegbar.
  - Zusammenfuehrung mit Eventim/Reservix erfolgt spaeter in separater Pipeline.

## 5. Komponente B: Redaktions-Backend

### 5.1 Ziel
- Sehr effiziente Bearbeitung grosser Mengen importierter Events.

### 5.2 Kernfunktionen
- Login-geschuetztes Backend (Rails Authentication Generator)
- Event-Inbox mit Status-Spalten:
  - `imported`
  - `needs_review`
  - `ready_for_publish`
  - `published`
  - `rejected`
- Bearbeiten/Ergaenzen:
  - Titel, Artist, Genre, Beschreibung, Banderole, Bild, YouTube, CTA-Link
- Manuelle Neuerfassung von Veranstaltungen
- Einzel- und Bulk-Aktionen:
  - Publish/Unpublish
  - Mark as complete/incomplete
  - Bulk-Genre/Banderole setzen
- Kein Bearbeitungs-Locking in v1 (last-write-wins, mit Audit-Historie)

### 5.3 UX-Design fuer hohe Redaktionseffizienz
- Split-View: Liste links, Detail-Form rechts
- gespeicherte Filter (z. B. nur `needs_review`)
- Inline-Validierung + klare Fehlermeldungen
- Autosave fuer Form-Entwuerfe
- Turbo Frames fuer schnelle Teil-Updates ohne Vollreload
- Turbo Streams fuer Live-Updates bei Statusaenderungen

### 5.4 Rollenmodell (initial)
- `editor`: bearbeiten + publishen + manuelle Import-Starts
- `admin`: Konfiguration, Importer-Steuerung, Nutzerverwaltung

## 6. Komponente C: Frontend

### 6.1 Listenansicht (Startseite)
- Chronologisches Grid (nur diese Sortierung)
- Karteninhalt:
  - Eventbild
  - Band/Kuenstlername
  - Genre
  - Datum
  - Venue
  - optionale Banderole
- UX:
  - schlichtes, modernes Design als Startpunkt
  - angenehmer Hover-Effekt
  - Infinite Scroll (kein Paging)
  - performantes Nachladen per Turbo Frame/Stimulus Intersection Observer

### 6.2 Detailseite
- Strukturierte Darstellung aller Eventinformationen
- Optional eingebettetes YouTube-Video
- Klar sichtbarer CTA zum Ticketshop (provider-priority-basiert)
- SEO-Basis:
  - semantische Struktur
  - OpenGraph/Twitter Meta
  - kanonische URL
  - stabile Slugs (Slug bleibt nach Erstveroeffentlichung unveraendert)

### 6.3 Responsive & Performance
- Mobile-first Tailwind-Layout
- Bilder in passenden Groessen, lazy loading
- Query-Optimierung und Caching fuer Listen

## 7. Datenmodell (Initialer Vorschlag)
- `easyticket_import_events` (importierte Easyticket-Datensaetze)
  - `external_event_id`, `concert_date`, `city`, `venue_name`, `title`, `artist_name`
  - `concert_date_label`, `venue_label`
  - `dump_payload` (JSONB), `detail_payload` (JSONB)
  - `ticket_url`, `image_url`, `is_active`, `first_seen_at`, `last_seen_at`, `source_payload_hash`
  - unique: `(external_event_id, concert_date)`
- `eventim_import_events` (importierte Eventim-Datensaetze, analog aufgebaut)
- `reservix_import_events` (importierte Reservix-Datensaetze, analog aufgebaut)
- `events` (zusammengefuehrte, redaktionell gefuehrte Datensaetze fuer Frontend)
  - `slug`, `title`, `artist_name`, `start_at`, `venue`, `city`, `event_info`
  - `badge_text`, `editor_notes`, `status`, `published_at`, `published_by_id`
  - `completeness_score`, `completeness_flags`
  - `primary_source`, `auto_published`
- `event_offers` (provider-spezifische Ticket/Preis-Angebote je Event; wird in Merge-Pipeline erzeugt)
  - `event_id`, `source_event_id`, `source`, `ticket_url`, `ticket_price_text`, `sold_out`, `priority_rank`
- `genres`, `event_genres`
- `import_runs`, `import_run_errors`, `event_change_logs`
- `import_sources`, `import_source_configs`, `provider_priorities`
- `users`, `sessions` (durch Rails Auth-Generator)

Wichtige DB-Indizes:
- `(status, start_at)` auf `events`
- `(published_at, start_at)` auf `events`
- `(is_active, concert_date)` auf `easyticket_import_events`
- `(external_event_id, concert_date)` unique auf `easyticket_import_events`
- `(is_active, concert_date)` auf `eventim_import_events`
- `(is_active, concert_date)` auf `reservix_import_events`
- `slug` unique auf `events`

## 8. Hotwire-/UI-Architektur
- Turbo Drive fuer Navigation
- Turbo Frames:
  - Eventliste
  - Editor-Panel
  - Importer-Config-Formulare
- Turbo Streams:
  - Live-Aktualisierung von Listenzeilen/Status-Badges
  - Run-Status-Updates fuer manuell gestartete Importe
- Stimulus Controller:
  - Infinite Scroll
  - Filter State
  - Keyboard Shortcuts
  - Media-Preview (Bild/YouTube)

## 9. API-/Importer-Implementierungsstrategie
- Modulstruktur:
  - `app/services/importing/connectors/*`
  - `app/services/importing/normalizers/*`
  - `app/services/importing/upsert/*`
  - `app/services/importing/runs/*`
  - `app/services/merging/*`
- Eventim-Feed als Streaming-Parse (speicher-effizient)
- Source-spezifische Mappings gemaess `Importer Information` verwenden
- Einheitliche Fehlerschnittstelle pro Connector (typed errors)
- Easyticket-Connector:
  - liest Eventliste ueber `XMP_DUMP_URL`
  - laedt Details ueber `EVENT_DETAIL_API` je `event_id`
  - persistiert Roh-JSON + Projektionen in `easyticket_import_events`
- Merge-Service:
  - bildet Event-Fingerprints
  - mappt `easyticket_import_events`, `eventim_import_events`, `reservix_import_events` auf `events`
  - bestimmt `primary_source` anhand konfigurierbarer Prioritaeten
  - schreibt `event_offers` in deterministischer Reihenfolge

## 10. Teststrategie
- Unit Tests:
  - Normalizer
  - Completeness Checker
  - Merge-/Prioritaetslogik
  - Publishing-Regeln
- Integration Tests:
  - End-to-End Import je Quelle (mit Fixture-Payloads)
  - idempotente Doppel-Imports
  - manuelles Triggern von Import-Jobs im Backend
- System Tests (Capybara):
  - Redaktions-Workflow inkl. Bulk-Aktionen
  - Frontend Infinite Scroll + Detailseite
  - Ticket-CTA-Fallback gemaess Prioritaetsreihenfolge
- Nicht-funktional:
  - Performance Smoke Test fuer grosse Eventmengen

## 11. Delivery-Phasen
- Phase 0: Projekt-Setup
  - Rails-App, Tailwind, Auth-Generator, Solid Queue, CI-Grundgeruest
- Phase 1: Infrastruktur-Basis
  - Terraform-Setup, AWS-Umgebungen (staging/production), Kamal-Basisdeployment
- Phase 2: Domain & Datenbank
  - Kernschema (`easyticket_import_events`, `eventim_import_events`, `reservix_import_events`, `events`, `event_offers`), States, Indizes
- Phase 3: Importer v1
  - Easyticket zuerst: `XMP_DUMP_URL` -> Ortsfilter -> `EVENT_DETAIL_API` -> JSON-Persistenz
  - Run-Tracking, Retry, Artefakt-Logging, manuelle Trigger
- Phase 4: Weitere Importer v1
  - Eventim + Reservix mit gleichem Persistenzmuster (eigene Tabellen)
- Phase 5: Merge + Redaktions-Backend v1
  - Source-uebergreifendes Zusammenfuehren, Inbox, Edit, manuell erfassen, Publish
- Phase 6: Frontend v1
  - Grid, Infinite Scroll, Detailseiten, CTA nach Provider-Prioritaet
- Phase 7: Datenqualitaet & Auto-Publish
  - Completeness-Engine, Regelwerk, Monitoring
- Phase 8: Hardening & Launch
  - Lasttests, Fehlerbehebung, SEO-Checks, Go-Live

## 12. Betrieb, Monitoring, Sicherheit
- Structured Logging pro Run/Job
- Dashboards:
  - Run-Erfolg pro Quelle
  - Importdauer
  - Qualitaetskennzahlen
  - Merge-Quote und Auto-Publish-Quote
- Alerts:
  - 2 fehlgeschlagene Runs in Folge je Quelle
  - starker Volumenabfall oder Deaktivierungs-Spike
- Secrets ausschliesslich via AWS Secrets Manager/SSM Parameter Store
- Rollen- und Session-Sicherheit fuer Backend
- Kein externes Analytics-Tracking in v1

## 13. Infrastruktur-Provisionierung (Terraform + AWS + Kamal)
- Terraform-Struktur:
  - `infrastructure/terraform/modules/*` (network, security, compute, db, storage, iam, monitoring)
  - `infrastructure/terraform/envs/staging`
  - `infrastructure/terraform/envs/production`
- Terraform State:
  - Remote State in S3
  - State Locking via DynamoDB
- AWS Zielarchitektur:
  - VPC mit Public/Private Subnets
  - Security Groups mit minimalen Regeln
  - EC2-Hosts fuer App-Rollen (web/worker/scheduler via Kamal)
  - RDS PostgreSQL 18 (staging klein, production mit Backup- und Restore-Strategie)
  - ECR fuer Docker Images
  - S3 fuer Active Storage/Import-Artefakte
  - CloudWatch Logs + Alarme
  - Route53 + ACM fuer DNS/TLS
- Deployment Flow:
  - CI baut Docker Image und pusht nach ECR
  - Kamal deployt auf EC2 (rolling deploy, health checks, rollback)
  - getrennte Kamal-Configs fuer staging/production

## 14. Festgelegte Produktentscheidungen
1. Design: vorerst schlicht, ohne festes bestehendes Design-System.
2. `ready_for_publish` Datensaetze werden automatisch publisht.
3. Source-uebergreifende Duplikate werden zusammengefuehrt.
4. Provider-Prioritaet ist konfigurierbar; Startwert: `reservix -> eventim -> easyticket`.
5. Import-Frequenz ist taeglich; einzelne Importe sind zusaetzlich manuell ueber die UI triggerbar.
6. Ticketshop-Link folgt derselben Provider-Prioritaet wie das Merge.
7. Mediennutzung wie im aktuellen System (Bilder/Videos werden ausgespielt).
8. SEO: permanente Slugs bleiben stabil.
9. Deployment-Ziel: Docker mit Kamal.
10. Analytics: keine Integration in v1.
11. Jeder Importer erhaelt eine eigene Importtabelle (`easyticket_import_events`, `eventim_import_events`, `reservix_import_events`).
12. Implementierungsreihenfolge der Importer startet mit Easyticket.

## 15. Optimierungen fuer robustere Importer (ergaenzend)

### 15.1 Provider-Resilienz
- Source-spezifische Queue-Trennung (`imports_reservix`, `imports_eventim`, `imports_easyticket`) mit Concurrency-Limits.
- Retry mit Exponential Backoff + Jitter (nicht nur fixe Backoff-Stufen).
- Circuit Breaker je Source (bei wiederholten 5xx/Timeouts automatische Pausierung + Alarm).
- Manueller Retry-Button pro fehlgeschlagenem Run im Backend.

### 15.2 Parse- und Schema-Robustheit
- Eventim strikt als Streaming-Parser mit recordweiser Fehlerisolierung (ein defekter Block stoppt nicht den gesamten Run).
- `import_dead_letters` Tabelle fuer nicht verarbeitbare Rohdatensaetze (inkl. Fehlercode + Rohsnippet + Source-ID).
- Schema-Drift-Erkennung:
  - Zaehler fuer unbekannte/entfallene Felder pro Provider.
  - Alarm bei auffaelligen Abweichungen gegen 14-Tage-Baseline.

### 15.3 Datenqualitaet (vor Persistenz)
- Placeholder-Bilder aktiv filtern (z. B. `blank.gif`, Provider-Logos) und fallback auf naechstbessere Quelle.
- URL-Health-Checks asynchron (HEAD/GET) fuer Ticket- und Bild-URLs; defekte Links markieren.
- Zeit-Praezision speichern (`time_known` Flag), wenn Source keine Uhrzeit liefert.
- Provider-normalisierte Preisvalidierung mit Grenzwertchecks (z. B. negative/absurde Werte verwerfen).

### 15.4 Merge-Robustheit source-uebergreifend
- `merge_confidence` Score pro Match (hoch/mittel/niedrig) statt nur deterministischer Fingerprint.
- Nur hohe Confidence automatisch zusammenfuehren; mittlere/niedrige Confidence in redaktionelle Merge-Queue.
- `event_merge_overrides` fuer manuelle Korrektur + "nie wieder mergen"/"immer mergen" Regeln.
- Ticket-CTA-Fallback-Kette automatisch bei sold-out/ungueltigem Link des primaeren Providers.

### 15.5 Laufsteuerung und Sicherheit
- Dry-Run Modus fuer manuell gestartete Imports (Preview ohne DB-Write).
- "No deactivate on failed run" beibehalten und um "2 consecutive missing runs" als optionalen Safety-Mode ergaenzen.
- Secret-Hygiene:
  - keine Credentials in Artefakten/Logs.
  - Easyticket-Dump-URLs mit Passwort niemals persistieren.
