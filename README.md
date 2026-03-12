# stuttgart-live.de

stuttgart-live.de ist ein lokales Stadtmagazin für Veranstaltungen, Kultur und Freizeittipps in Stuttgart. Die Anwendung sammelt Termine aus verschiedenen Quellen, bereitet sie redaktionell auf und macht sie in einer klaren, schnellen Oberfläche zugänglich.

Im Mittelpunkt steht ein unkompliziertes Nutzungserlebnis: Besucherinnen und Besucher sollen schnell relevante Events finden, sich inspirieren lassen und über den Newsletter mit neuen Empfehlungen versorgt werden. Dieses Repository enthält die technische Grundlage dafür.

## Technischer Überblick

- Framework: Ruby on Rails 8.1
- Sprache: Ruby 3.x
- Datenbank: PostgreSQL
- Frontend: Hotwire (Turbo, Stimulus), Tailwind CSS 4, esbuild
- Hintergrundverarbeitung: Solid Queue
- Caching und Echtzeit-Infrastruktur: Solid Cache, Solid Cable
- Medien und Rich Text: Active Storage, Action Text
- Deployment: Docker-basierte Auslieferung mit Kamal auf Hetzner
- Test-Stack: Rails/Minitest, Capybara, Selenium

Die Anwendung ist bewusst als klassischer Rails-Monolith aufgebaut. Öffentliche Seiten, redaktionelles Backend, Importlogik, Hintergrundjobs und Infrastruktur leben im selben Repository und teilen sich ein gemeinsames Domänenmodell.

## Produktbereiche

- Öffentliche Website: Event-Listing, Event-Detailseiten, News, statische Informationsseiten und Newsletter-Anmeldung
- Redaktionelles Backend: Pflege von Events, Blog-Inhalten, Importquellen, Importläufen, Bildern und Benutzerkonten
- Import-Pipeline: Anbindung externer Anbieter wie Easyticket, Eventim und Reservix
- Redaktionelle Verarbeitung: Zusammenführen importierter Daten, Qualitäts- und Vollständigkeitsprüfungen, Protokollierung von Änderungen
- Content-Erweiterungen: Blog-Import aus WordPress sowie Newsletter-Synchronisation mit Mailchimp

## Architektur

### Anwendungsstruktur

- `app/controllers/public`: Öffentliche Endpunkte für Website, News und Newsletter
- `app/controllers/backend`: Internes Redaktions- und Administrations-Backend
- `app/models`: Zentrale Domänenmodelle wie `Event`, `ImportSource`, `ImportRun`, `BlogPost` und `NewsletterSubscriber`
- `app/services`: Fachlogik für Import, Redaktion, Zusammenführung, Blog und Newsletter
- `app/queries`: Abfrageobjekte für strukturierte Lesezugriffe, zum Beispiel für öffentliche Event-Listen oder redaktionelle Inboxen
- `app/jobs`: Asynchrone Verarbeitung für Importe, Merge-Prozesse und Newsletter-Sync
- `app/presenters`: Darstellungsspezifische Aufbereitung für Backend- und Public-Views
- `app/javascript/controllers`: Stimulus-Controller für progressive Interaktivität
- `lib/tasks`: Operative Rake-Tasks, etwa für Hintergrund- oder Nachverarbeitungsjobs

### Schichtenmodell

1. Router und Controller nehmen HTTP-Anfragen entgegen und trennen klar zwischen öffentlicher Oberfläche und Backend.
2. Modelle halten Persistenzregeln, Beziehungen, Validierungen und einfache Domäneninvarianten.
3. Services kapseln fachliche Abläufe, die über einzelne Modelle hinausgehen, etwa Datenimporte, Zusammenführungen oder externe API-Aufrufe.
4. Queries bilden wiederverwendbare, lesbare Datenzugriffe für Listen- und Inbox-Ansichten.
5. Jobs verschieben langsame oder externe Arbeit in den Hintergrund, damit Requests kurz bleiben.

### Routing

Das Routing in `config/routes.rb` folgt einer klaren Trennung:

- Öffentliche Routen unter Root, `/events`, `/news` sowie einzelnen statischen Seiten
- Session- und Passwort-Flows für Login und Account-Zugriff
- Backend-Routen unter `/backend` für Redaktion und Importverwaltung
- Fehlerseiten werden über `ErrorsController` und `config.exceptions_app = routes` direkt durch die Anwendung gerendert

## Domänenmodell

Wichtige Aggregate und ihre Aufgaben:

- `Event`: Zentrale veröffentlichbare Veranstaltung mit redaktionell gepflegten Daten
- `EventImage`, `EventOffer`, `EventChangeLog`: Ergänzende Medien-, Angebots- und Änderungsinformationen
- `ImportSource`, `ImportSourceConfig`, `ImportRun`, `ImportRunError`: Steuerung, Ausführung und Beobachtung der Importprozesse
- `EasyticketImportEvent`, `EventimImportEvent`, `ReservixImportEvent`: Anbieterbezogene Rohdatenmodelle
- `BlogPost`: Redaktionelle Inhalte und importierte Beiträge
- `NewsletterSubscriber`: Newsletter-Anmeldungen inklusive optionalem Mailchimp-Sync
- `User`, `Session`: Authentifizierung und Backend-Zugriff

## Authentifizierung und Login-Schutz

Der Login für den redaktionellen Bereich ist zusätzlich gegen einfache Brute-Force-Angriffe abgesichert.

- Fehlgeschlagene Login-Versuche werden protokolliert
- Nach mehreren Fehlversuchen wird das betroffene Benutzerkonto temporär gesperrt
- Erfolgreiche, fehlgeschlagene und gesperrte Anmeldeversuche werden als Login-Historie gespeichert
- Passwort-Änderungen und Benutzeranlage unterliegen einer Mindestanforderung an starke Passwörter

## Datenfluss

### Event-Import und Redaktion

1. Importquellen werden im Backend konfiguriert.
2. Hintergrundjobs oder manuelle Backend-Aktionen starten Importläufe.
3. Anbieterbezogene Rohdaten werden in Importtabellen geschrieben.
4. Services in `app/services/importing` und `app/services/merging` gleichen Daten ab, führen sie zusammen und übertragen sie in die redaktionellen Event-Modelle.
5. Das Backend erlaubt Sichtung, Korrektur, Veröffentlichung und Qualitätskontrolle.
6. Öffentliche Listen greifen über Query-Objekte auf veröffentlichte Inhalte zu.

### Newsletter

1. Öffentliche Anmeldungen werden lokal in `newsletter_subscribers` gespeichert.
2. Wenn Mailchimp konfiguriert ist, wird zusätzlich ein Hintergrundjob zum externen Sync eingeplant.
3. Der Sync-Status bleibt am Datensatz nachvollziehbar, damit fehlgeschlagene Übertragungen erneut verarbeitet werden können.

## Frontend

Das Frontend ist serverseitig gerendert und nutzt Hotwire für gezielte Interaktivität statt eines separaten SPA-Clients.

- HTML-Rendering erfolgt über klassische Rails-Views
- Navigation und inkrementelle Updates laufen über Turbo
- Interaktive Komponenten liegen als Stimulus-Controller in `app/javascript/controllers`
- CSS wird mit Tailwind CSS 4 gebaut
- JavaScript-Bundles entstehen über esbuild

Diese Architektur hält die Komplexität niedrig und erlaubt trotzdem schnelle Oberflächen sowie progressive Erweiterungen im Backend und auf den öffentlichen Seiten.

## Entwicklung

### Lokale Voraussetzungen

- Ruby in passender Projektversion
- PostgreSQL
- Node.js und npm

### Wichtige Kommandos

```bash
bin/setup
bin/dev
bin/rails test
bin/ci
```

`bin/dev` startet die lokale Entwicklungsumgebung mit Webserver, Job-Worker sowie JavaScript- und CSS-Watchern. Das zugrunde liegende Prozessmodell ist in `Procfile.dev` definiert.

### Konfiguration

Wichtige Umgebungsvariablen:

- `GOOGLE_ANALYTICS_ID` aktiviert GA4 nach Einwilligung im Consent-Banner
- `MAILCHIMP_API_KEY` plus `MAILCHIMP_LIST_ID` aktivieren den optionalen Mailchimp-Sync für Newsletter-Anmeldungen
- `MAILCHIMP_SERVER_PREFIX` kann explizit gesetzt werden und ist bei euch voraussichtlich `us3`
- `EASYTICKET_*`, `EVENTIM_*`, `RESERVIX_*` steuern die Importanbindungen externer Anbieter
- `DB_*` und `RAILS_MASTER_KEY` sind für Laufzeit und Deployment erforderlich

Ohne Mailchimp-Konfiguration bleibt die lokale Speicherung von Newsletter-Anmeldungen aktiv, es erfolgt dann aber kein externer Sync.

## Qualitätssicherung

Das Projekt bündelt die Standardprüfungen in `bin/ci`. Dabei laufen aktuell:

- Setup über `bin/setup --skip-server`
- Ruby-Linting mit RuboCop
- Sicherheitsprüfungen mit Bundler Audit, `yarn audit` und Brakeman
- Testlauf mit `bin/rails test`
- Seed-Prüfung im Testsystem

Vor einem Push sollte `bin/ci` erfolgreich durchlaufen.

## Deployment und Betrieb

- Das produktive Deployment läuft über Kamal
- Das Zielsystem ist aktuell Hetzner
- Die Konfiguration liegt in `config/deploy.hetzner.yml`
- GitHub Actions übergeben die benötigten Secrets an den Deploy-Prozess
- Produktionsnahe Infrastrukturhinweise liegen ergänzend in `HETZNER.md` und `INFRA.md`

Im Produktionsbetrieb werden Webprozess und Job-Verarbeitung gemeinsam innerhalb der Rails-Anwendung betrieben. `SOLID_QUEUE_IN_PUMA=true` ist für das Hetzner-Deployment bereits vorgesehen.

## Weiterführende Dateien

- `config/routes.rb`: Einstieg in die fachliche Struktur der HTTP-Oberfläche
- `app/services/`: Zentrale Geschäftslogik
- `app/queries/`: Lesezugriffe und Listenlogik
- `app/jobs/`: Hintergrundverarbeitung
- `config/ci.rb`: Aufbau der CI-Prüfschritte
- `config/deploy.hetzner.yml`: Produktionsdeployment
