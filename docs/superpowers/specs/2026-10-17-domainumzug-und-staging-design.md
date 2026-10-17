# Domainumzug und Staging für Stuttgart Live und Russ Live

Stand: 17. Oktober 2026. Das Zielbild und der grundsätzliche Ablauf wurden im Gespräch abgestimmt. Diese schriftliche Spezifikation wird vor Erstellung des detaillierten Umsetzungsplans nochmals geprüft und freigegeben.

## Ziel und Umfang

Die beiden bestehenden Rails-Anwendungen bleiben auf dem gemeinsamen Hetzner-Server `46.225.224.194`. Ihre öffentlichen Adressen wechseln von den bisherigen `schopp3r.de`-Subdomains auf die endgültigen Domains. Beide Projekte erhalten zusätzlich eine getrennte Staging-Umgebung auf demselben Server.

| Projekt | Produktion | Staging |
| --- | --- | --- |
| Stuttgart Live | `https://stuttgart-live.de` | `https://staging.stuttgart-live.de` |
| Russ Live | `https://russ-live.de` | `https://staging.russ-live.de` |

Die Hauptadressen verwenden kein `www`. Die jeweiligen `www`-Adressen erhalten gültiges HTTPS und leiten mit erhaltenem Pfad und Querystring dauerhaft auf die Hauptadresse weiter, auch bei Assets und Medien.

Die Domainverwaltung bleibt bei Host Europe beziehungsweise STRATO. Ein Registrar- oder Nameserverwechsel gehört nicht zum Umzug. **Alle bestehenden DNS-Einträge, die nicht das Webangebot betreffen, müssen unverändert bleiben. Microsoft 365 muss während und nach dem gesamten Umzug weiterhin funktionieren.** Diese Vorgabe gilt für Vorbereitung, Staging-Einrichtung, Livegang und Rückfall gleichermaßen.

Die zunächst gewünschten Adressen `old.stuttgart-live.de` und `old.russ-live.de` entfallen nach ausdrücklicher Abstimmung. Die bisherige WordPress-Seite von Stuttgart bleibt unverändert für ein kurzes Rückfallfenster auf ihrem bisherigen Hosting bestehen. Für internes Nachschlagen reicht eine lokale hosts-Zuordnung. `www.michaelrussgmbh.de` bleibt zunächst unverändert erreichbar; seine spätere Weiterleitung auf `https://russ-live.de` ist ein nachgelagerter Schritt.

## Ausgangszustand und Grenzen der Bestandsaufnahme

Am 17. Oktober 2026 wurden DNS, HTTP-Antworten, beide lokalen Repositories und der Hetzner-Host lesend geprüft:

- Beide Rails-Anwendungen laufen auf `46.225.224.194`, jeweils mit einer Kamal-Web- und einer Job-Rolle. Der gemeinsame Proxy verwendet `kamal-proxy:v0.9.2`.
- Stuttgart Live wurde auf dem Host mit Image-Version `6ab33f9a972dc3532110b3f55ed683c300df2989`, Russ Live mit `14b1d2f7e4237d5cfe1ccb39950619141891e8ea` beobachtet. Diese Werte werden vor Umsetzung erneut erfasst; sie sind keine vorgegebene Release-Basis.
- Der Host besitzt rund 7,6 GiB Arbeitsspeicher. Bei der Momentaufnahme waren rund 4,7 GiB verfügbar und rund 49 GiB auf dem Root-Dateisystem frei. Das ersetzt keine Kapazitätsprüfung unter repräsentativem Betrieb und während eines Deployments.
- `stuttgart-live.de` zeigt per A-Eintrag auf `83.169.28.13` und besitzt einen AAAA-Eintrag zum bisherigen Hosting. Für AAAA wurde eine TTL von 21.600 Sekunden beobachtet.
- `russ-live.de` zeigt per A-Eintrag auf `217.160.0.49`, besitzt ebenfalls einen bisherigen AAAA-Eintrag und antwortet mit einer 301-Weiterleitung auf `http://www.michaelrussgmbh.de`.
- Die MX-Einträge beider Domains zeigen auf Microsoft 365. Bei Stuttgart sind `ns27.domaincontrol.com` und `ns28.domaincontrol.com` autoritativ, bei Russ `docks07.rzone.de` und `shades02.rzone.de`. Die Verwaltungsoberfläche muss jeweils Die tatsächlich die aktive Zone ändern.
- Beide bisherigen Rails-Adressen liefern HTTPS und global `X-Robots-Tag: noindex, nofollow`. Die bisher als Staging bezeichneten Deployments sind die bestehenden Produktionsdienste; eine zusätzliche isolierte Staging-Umgebung existiert in den geprüften Konfigurationen noch nicht.
- Beide Projekte veröffentlichen derzeit Pushes auf `main` automatisch in Produktion. Der neue Ablauf ersetzt dieses Verhalten.
- Der direkte Abruf von `http://83.169.28.13` scheitert mit 403; HTTPS über die IP scheitert an der Zertifikatsprüfung. Derselbe Server liefert mit dem ursprünglichen Hostnamen `stuttgart-live.de` eine erfolgreiche Antwort.

Der Nutzer besitzt Zugänge zur Domainverwaltung von Host Europe und STRATO, aber keinen Zugang zum bisherigen WordPress-Hosting und derzeit keinen Kontakt zum Betreiber. Ein vollständiges WordPress-Backup, Änderungen an WordPress und die spätere Abschaltung sind deshalb nicht selbstständig ausführbar. Eine vollständig eigenständige Sicherung dieser Website wird nicht vorausgesetzt oder zugesagt.

Der Entwurf vom 13. Oktober 2026 beschreibt einen früheren Umfang ohne getrenntes Staging. Für dieses Vorhaben ist die vorliegende Spezifikation maßgeblich. Vorhandene ältere Arbeitsdateien werden nicht überschrieben.

## Architektur und Trennung der Umgebungen

### Gemeinsame Betriebsgrundlage

Beide Umgebungen verwenden dieselben Softwareversionen und dieselbe Betriebsweise: Docker-Images je Projekt, nginx und Puma, PostgreSQL sowie Solid Queue, Cache und Cable. Auch Staging läuft mit `RAILS_ENV=production`, damit Asset-Verarbeitung, Caching, Fehlerdarstellung und Prozessmodell der Produktion entsprechen.

Das Deployment unterscheidet Produktion und Staging ausdrücklich über seine Laufzeitkonfiguration. `Rails.env.production?` allein darf nicht darüber entscheiden, ob echte externe Aktionen zulässig sind. Der bestehende Produktions-Zielname `hetzner` bleibt erhalten; Staging erhält ein eigenes Kamal-Ziel `staging` mit unterscheidbaren Container-, Service- und Secret-Zuordnungen.

Der bestehende gemeinsame Proxy und die PostgreSQL-Instanz bleiben bestehen. Staging erhält eigene Container und begrenzte CPU-/Arbeitsspeicherressourcen. Als Ausgangspunkt dienen je App ein Webprozess mit wenigen Threads und ein kleiner Jobprozess. Die endgültigen Grenzen werden anhand des gemessenen Verbrauchs festgelegt und vor dem Livegang einschließlich gleichzeitig laufender alter und neuer Container geprüft. Produktion hat bei Kapazitätsengpässen Vorrang; Staging darf dafür angehalten werden.

Der gemeinsame Host, Proxy und PostgreSQL-Dienst bleiben gemeinsame Ausfallursachen. Die Trennung schützt Daten und Deployment-Zuordnungen; sie ersetzt keine separate physische Infrastruktur.

### Daten und Medien

| Ressource | Produktion | Staging |
| --- | --- | --- |
| Stuttgart-Fachdaten | Bestehende `stuttgart_live_de_production` | Eigene `stuttgart_live_de_staging` |
| Russ-eigene Daten | Bestehende `russ_live_de_production` | Eigene `russ_live_de_staging` |
| Cache, Queue und Cable | Bestehende getrennte Datenbanken je App | Eigene Datenbanken je App mit Staging-Namen |
| Gemeinsame Medien je Projektpaar | `stuttgart_live_de_storage` | Neues `stuttgart_live_de_staging_storage` |
| Datenbankbenutzer und Secrets | Bestehende Produktionszuordnung | Eigene Staging-Zuordnung ohne Datenrechte auf Produktion |

Stuttgart Live bleibt Eigentümer seiner fachlichen Datenbank. Russ Live liest freigegebene Stuttgart-Daten weiterhin über einen eigenen Benutzer mit Leserechten und führt seine eigenen Daten in separaten Datenbanken. Genau diese Beziehung wird innerhalb von Staging nachgebildet: Russ-Staging liest ausschließlich Stuttgart-Staging und verwendet dessen Medienkopie.

Die bestehenden Produktionsdatenbanken und Medien werden beim Domainwechsel nicht verschoben oder durch Staging ersetzt. Alle Datenbanknamen einschließlich Queue, Cache und Cable sowie das explizit benannte Docker-Volume müssen je Deployment-Ziel gesetzt werden. Ein abweichender Hostname oder Kamal-Zielname allein trennt diese Ressourcen nicht.

Staging-Benutzer dürfen Produktionsdaten weder lesen noch verändern. Entsprechende Negativprüfungen gehören zur Abnahme. Zugriffe eines Staging-Containers auf Produktionsdaten oder das Produktions-Medienvolume sind ein Abbruchgrund.

### Erstbefüllung und spätere Aktualisierung

Staging erhält eine zusammenpassende Kopie der fachlichen Daten beider Projekte und der zugehörigen Medien. Vor der ersten Erreichbarkeit und vor dem Start von Workern wird die Kopie bereinigt:

- Personenbezogene Daten wie Newsletter-Adressen und Nutzerinformationen entfernen oder durch synthetische Testdaten ersetzen.
- Sitzungen, Rücksetzlinks, Anmeldetokens, OAuth-Verbindungen und externe Integrationstokens entfernen beziehungsweise invalidieren; eigene Staging-Testkonten bereitstellen.
- Warteschlangen, geplante Ausführungen und Caches leer neu anlegen, statt Produktionsjobs zu übernehmen.
- Zuordnungen zwischen Events, Russ-Freigaben und Medien erhalten und anhand repräsentativer Inhalte prüfen.

Eine Datenaktualisierung erfolgt nur manuell bei Bedarf. Sie überschreibt bewusst Staging-Testdaten und läuft bei angehaltenen betroffenen Staging-Prozessen. Danach folgen erneut Bereinigung, Migrationen und eine Funktionsprüfung, bevor Worker und Zugriff freigegeben werden. Ein fehlgeschlagener Import bleibt auf Staging beschränkt und darf keine Produktionsressource zurücksetzen.

### Zugangsdaten und externe Aktionen

Staging erhält eigene Datenbankpasswörter, Sitzungsschlüssel, Medien-Signierschlüssel und eigene Laufzeit-Credentials. Die Auswahl der Credentials muss vom Deployment-Ziel abhängen, obwohl beide Ziele mit der Rails-Betriebsart `production` laufen. Staging erhält keine zur Entschlüsselung der Produktions-Credentials geeigneten Schlüssel.

In Stuttgart bevorzugt `AppConfig` derzeit Rails-Credentials gegenüber Umgebungsvariablen. Deshalb genügt es nicht, einzelne ENV-Werte zu leeren: Die Trennung und die Schutzregeln müssen auch einen Rückfall auf produktive Credentials verhindern.

E-Mails werden in einem internen Testpostfach aufgefangen. Direkte Mailjet-Aktionen, Kontakt-/Listen-Synchronisation und Newsletter-Versand an echte Empfänger sind ebenfalls gesperrt; eine reine Action-Mailer-Umleitung reicht dafür nicht. Echte Social-Media-Veröffentlichungen bleiben gesperrt. Automatische externe Import- und kostenpflichtige KI-Läufe sind deaktiviert. Tests dieser Integrationen verwenden gezielt bereitgestellte Testdaten und Testzugänge.

Die Job-Verarbeitung bleibt als Betriebsprinzip vorhanden. Die Auswahl der Zeitpläne und die Schutzregeln müssen verhindern, dass die unter `production` konfigurierten Import-, Newsletter- oder Meta-Aufgaben unbeabsichtigt in Staging aktiv werden. Fehlererfassung und Release-Meldungen unterscheiden `staging` und `production`.

Staging erhält Passwortschutz und `X-Robots-Tag: noindex, nofollow`, auch für Assets und Medien. Der interne Healthcheck muss weiterhin funktionieren. Der Suchmaschinen-Header ergänzt den Zugangsschutz.

## Veröffentlichung und Zusammenarbeit beider Projekte

Für beide Repositories gilt künftig:

1. Ein neuer Stand auf `main` durchläuft die vollständigen CI-Prüfungen.
2. Erst nach erfolgreicher Prüfung wird je Projekt ein Docker-Image gebaut und über Commit und Image-Digest eindeutig identifiziert.
3. Dieses Image wird automatisch auf das zugehörige Staging ausgerollt.
4. Nach der inhaltlichen Prüfung wird genau diese erfolgreich auf Staging bereitgestellte Version manuell für Produktion freigegeben.
5. Produktion verwendet dasselbe Image ohne Neubau. Ein beweglicher Tag wie `latest` ist keine ausreichende Versionsangabe.

Die Freigabe bezieht sich auf eine konkrete Version, auch wenn inzwischen weitere Änderungen auf Staging angekommen sind. Auch die geprüften Peer-Images werden mit Image-Name, Commit und Digest gebunden. Ein anderer Digest bei gleichem Commit erfordert einen neuen Kompatibilitätsnachweis. Die Zuordnung von Commit, Image und erfolgreichem Staging-Deployment muss nachvollziehbar bleiben. Produktions- und Staging-Secrets sind getrennten Deployment-Zielen zugeordnet. Ein Push auf `main` darf Produktion nicht mehr unmittelbar verändern.

Da Russ Live die Stuttgart-Datenbank liest, wird bei Datenmodelländerungen die Kombination beider App-Versionen geprüft. Stuttgart-Migrationen müssen zur noch laufenden Russ-Version kompatibel sein. Ein App-Rollback setzt ein kompatibles Datenbankschema voraus; für den reinen Domainwechsel werden keine destruktiven Datenmigrationen eingeführt.

Deployments derselben Umgebung werden zwischen beiden Repositories koordiniert. GitHub-Concurrency-Gruppen allein sichern keine repositoryübergreifenden Eingriffe auf dem Host ab. Änderungen am gemeinsamen Proxy und vergleichbare Host-Eingriffe benötigen eine gemeinsame Sperre beziehungsweise ein abgestimmtes Wartungsfenster. Ein gewöhnlicher App-Deploy soll keinen unnötigen Proxy-Neustart auslösen.

## Domainrouting, HTTPS und bestehende Links

Die Web-DNS-Einträge zeigen künftig auf Hetzner. Am Domain-Apex werden A-Einträge verwendet. Alte Web-AAAA-Einträge werden entfernt, sofern die vollständige IPv6-Erreichbarkeit einschließlich Routing und HTTPS nicht vorher positiv geprüft wurde. Das Vorhandensein einer Hetzner-IPv6-Adresse allein genügt nicht.

Bestehende Nicht-Web-Einträge sind unveränderlich: insbesondere MX, SPF, DKIM, DMARC, Autodiscover, Microsoft-365-Verifizierungen sowie sonstige CNAME-, TXT-, SRV- und andere Einträge für unabhängige Dienste. Ihre Werte, Prioritäten und individuell konfigurierten TTLs bleiben erhalten. Ebenso bleiben Nameserver, DNSSEC und bestehende CAA-Regeln unverändert. Es werden keine DNS-Zonen zurückgesetzt, vollständig ersetzt oder durch Anbieter-Assistenten auf Standardwerte umgestellt.

Zulässig sind ausschließlich die einzeln dokumentierten Web-Änderungen an Hauptdomain und `www`, die neuen Staging-Webeinträge sowie zusätzliche, für HTTPS erforderliche `_acme-challenge`-Validierungseinträge. Vorhandene TXT-Werte dürfen dabei nicht überschrieben werden; später entfernt werden nur die von diesem Vorhaben selbst hinzugefügten Validierungswerte. Änderungen für zusätzliche Mailjet-Verifizierungen oder andere Maildienste gehören nicht zum Umfang.

Vor jedem Eingriff wird der bestehende Stand gesichert. Danach werden die autoritativen Nicht-Web-Einträge einschließlich ihrer konfigurierten Eigenschaften mit der Sicherung verglichen. Automatisch geänderte SOA-Seriennummern sind von diesem Inhaltsvergleich ausgenommen. Vorab werden außerdem mögliche Abhängigkeiten von Maildiensten zu den zu ändernden Webhosts geprüft. Die Deaktivierung der STRATO-Weiterleitung wird mit den eigenen Web-DNS-Einträgen abgestimmt und nach dem Speichern nochmals vollständig kontrolliert. Würde ein notwendiger Schritt Nicht-Web-Einträge verändern oder Microsoft 365 beeinträchtigen, wird dieser Schritt angehalten und der Konflikt geklärt.

Für Produktions-Hauptdomains und `www` werden Zertifikate vorab per DNS-01 vorbereitet und die neuen HTTPS-Routen vor der Umschaltung gegen die Hetzner-IP geprüft. Die bisherigen `schopp3r.de`-Routen müssen nach ausdrücklicher Nutzerentscheidung nicht weiter erreichbar bleiben; DNS-Zugriff auf diese Zone und SANs für diese Hosts entfallen. Alle gleichzeitig bedienten Hostnamen müssen durch passende Zertifikate und eindeutige Proxy-Routen abgedeckt sein. Erforderliche DNS-Rechte und die tatsächlich verfügbare Proxy-Konfiguration werden vor diesem Schritt geprüft; ohne erfolgreichen Nachweis erfolgt keine Umschaltung.

Nach dem öffentlichen DNS-Wechsel übernimmt Kamals automatische Zertifikatsverwaltung. Diese Übergabe und die Erneuerung werden geprüft. Ein dauerhaft manuell gepflegtes Zertifikatsverfahren ist nicht vorgesehen. Staging kann seine Zertifikate nach Einrichtung der neuen Subdomain-DNS-Einträge automatisch erhalten.

Eigene Canonical-, Open-Graph-, strukturierte Daten-, Sitemap-, Newsletter- und Medienlinks verwenden die richtige Domain ihrer Umgebung. Die öffentlichen Hauptdomains erhalten keinen globalen Staging-Indexierungsschutz; fachlich gewollte `noindex`-Regeln bleiben bestehen. Domainbindungen externer Dienste, insbesondere Newsletter und Meta/OAuth, werden vorab angepasst und geprüft.

Wichtige bestehende Stuttgart-URLs werden erfasst und auf passende neue Inhalte abgebildet. Fehlende Inhalte werden bewusst behandelt; eine pauschale Weiterleitung aller Altpfade auf die Startseite ist nicht vorgesehen. Fremde Ticket-, Partner- und E-Mail-Adressen werden nicht durch eine pauschale Textersetzung verändert.

Die bisherigen `schopp3r.de`-Adressen dürfen bereits während der Vorbereitung entfallen. Vorhandene Funktionslinks, etwa Newsletter-Bestätigung und Abmeldung, werden vorab erfasst und ihre weitere Nutzung ausdrücklich bewertet; eine automatische Erreichbarkeit über alte Hosts wird nicht zugesagt. Die alten Hosts werden nicht als neue Staging-Adressen weitergenutzt. Der WordPress-Rückweg bleibt davon unabhängig über die gespeicherten Web-DNS-Werte beziehungsweise die lokale hosts-Zuordnung erhalten.

## Ablauf und Abnahmepunkte

### 1. Bestand und Rückweg sichern

DNS-Zonen, Weiterleitungseinstellungen, Hostrouten, Runtime-Konfiguration und tatsächlich laufende App-Versionen werden dokumentiert. Für die Rails-Datenbanken und Medien werden aktuelle, außerhalb der laufenden App-Ressourcen aufbewahrte Sicherungen sowie deren Wiederherstellbarkeit geprüft. Die Staging-Befüllung dient zusätzlich als praktische Wiederherstellungsprüfung. Das versionierte Host-Setup aktiviert Medienbackups nicht standardmäßig; daraus darf kein vorhandenes aktuelles Medienbackup abgeleitet werden.

Die aktive DNS-Verwaltung, erforderliche Zugänge, Zertifikatslaufzeiten und das Umschaltfenster werden vorab geprüft. Der bisherige WordPress-Server muss zum Umschaltzeitpunkt unter der ursprünglichen Domain über eine gezielte lokale Auflösung erreichbar sein. Sein Zertifikat muss das geplante Rückfallfenster abdecken. Bei nicht verfügbarem Rückweg wird vor dem Livegang angehalten und die Ursache geklärt.

### 2. Staging und den neuen Veröffentlichungsweg herstellen

Getrennte Datenbanken, Benutzer, Volumes, Credentials und Dienste werden eingerichtet. Die neuen Staging-Adressen erhalten DNS, HTTPS und Passwortschutz. Daten werden kopiert und bereinigt. Danach werden beide Apps, ihre Datenbeziehung und die manuelle Veröffentlichung einer konkret geprüften Version abgenommen.

### 3. Domains und Integrationen vorbereiten

Nur die TTLs der betroffenen Web-Einträge werden soweit möglich auf 300–600 Sekunden gesenkt. Globale Zonen-TTLs und die TTLs von Nicht-Web-Einträgen bleiben unverändert. Ermöglicht ein Anbieter keine getrennte Anpassung, wird die vorhandene TTL beibehalten und entsprechend gewartet. Vor dem Wechsel wird mindestens die bisherige maximale relevante TTL abgewartet; die beobachtete Stuttgart-AAAA-TTL entspricht sechs Stunden. Zertifikate, zusätzlich benötigte Hostrouten, Weiterleitungen, Indexierung und externe Domainbindungen werden vorbereitet, ohne die bisherigen öffentlichen Angebote vorzeitig umzuleiten.

### 4. Russ Live umschalten

Nach erfolgreichem HTTPS-Vorabtest wird die STRATO-Weiterleitung abgelöst und das Web-DNS umgestellt. Geprüft werden die richtige App, HTTPS einschließlich `www`, Pfade und Querystrings, freigegebene Stuttgart-Inhalte, Medien, Suche sowie die Russ-Anmeldung. Bereits zwischengespeicherte 301-Weiterleitungen werden mit einem frischen Browserprofil und unabhängigen HTTP-Prüfungen berücksichtigt. Erst nach erfolgreicher Abnahme folgt Stuttgart.

### 5. Stuttgart Live umschalten

Nach erfolgreichem Vorabtest werden die Web-DNS-Einträge umgestellt. Zusätzlich zur technischen Erreichbarkeit werden Eventseiten, Filter/Suche, Medien, Backend-Anmeldung, wichtige Altpfade, Newsletter-Bestätigung und Abmeldung sowie die vorbereiteten externen Integrationen geprüft. Echte Testsendungen oder Veröffentlichungen erfolgen ausschließlich gezielt an vereinbarte Testziele.

### 6. Beobachten und abschließen

WordPress bleibt mindestens 72 Stunden nach erfolgreicher Stuttgart-Abnahme unverändert auf seinem bisherigen Hosting. Voraussetzung für den Abschluss sind stabiler Betrieb und keine offenen Fehler, die einen Rückfall erfordern. Anschließend wird die Abschaltung beim bisherigen Betreiber veranlasst; die Ermittlung eines Ansprechpartners läuft parallel und ist eine externe Abhängigkeit.

Während des Fensters werden Fehlererfassung, Erreichbarkeit, Zertifikate, Mailfunktion, 404-Aufkommen und Serverressourcen kontrolliert. Danach werden ausschließlich zuvor abgesenkte Web-TTLs auf normale Betriebswerte angehoben. Beide READMEs dokumentieren Domains, Veröffentlichungen, Staging-Datenaktualisierung, externe Schutzregeln, Zertifikate und den Rückweg. Der bereits vorhandene README-Arbeitsstand wird dabei berücksichtigt.

## Rückweg und Grenzen

Bei einem kritischen Fehler wird die nächste Umschaltung gestoppt. Zuerst werden die betroffene App-Version sowie Host-, Proxy-, Zertifikats- und Laufzeitkonfiguration geprüft und nötigenfalls zurückgestellt. Ein funktionierendes anderes Projekt wird nicht zurückgesetzt.

Falls Stuttgart wieder öffentlich auf WordPress zurückfallen muss, werden ausschließlich die durch den Umzug geänderten Web-DNS-Einträge gezielt auf ihre gesicherten Werte zurückgestellt. Ein vollständiger Zonenimport ist kein Rückfallschritt; Nicht-Web-Einträge bleiben auch dabei unverändert. Bei Russ kann die gesicherte bisherige Weiterleitung kurzfristig wiederhergestellt werden, sofern der Anbieter dabei keine unabhängigen DNS-Einträge verändert. Die Hetzner-Routen bleiben während auslaufender DNS-Caches weiter bedienbar. Ein DNS-Rückweg ist nicht augenblicklich wirksam.

Die Rails-Datenbanken und Medien werden durch diesen Rückweg nicht zurückgesetzt. WordPress zeigt seinen bisherigen Datenstand; seitdem in Rails geänderte Inhalte werden nicht automatisch nach WordPress übertragen. Während der Umstellung werden konkurrierende Deployments und Newsletter-Kampagnen vermieden.

Für internes Nachschlagen kann auf ausgewählten Rechnern eine hosts-Zuordnung verwendet werden:

```text
83.169.28.13 stuttgart-live.de www.stuttgart-live.de
```

Damit öffnet die ursprüngliche Domain nur auf diesen Rechnern den bisherigen Server. Zum Prüfen der neuen Produktion wird die Zuordnung entfernt und gegebenenfalls der lokale DNS-Cache geleert. Das ist kein öffentliches Archiv und kein Backup. Die Nutzbarkeit endet mit der Abschaltung des bisherigen Hostings beziehungsweise bei Ablauf seines Zertifikats. Die tatsächliche Abschaltung bleibt ohne Betreiberzugang außerhalb unserer Kontrolle.

## Verifikation und Freigabebedingungen

Der detaillierte Umsetzungsplan muss folgende Nachweise vorsehen:

- Vollständig erfolgreiche CI in beiden Projekten; alle Ruby-/Bundler-Kommandos laufen über `mise exec -- ...`. Geänderte Ruby-Dateien werden zusätzlich gezielt mit RuboCop geprüft.
- Vor jedem Push Remote-Stand holen, Branch per Fast-forward oder Rebase aktualisieren und danach erneut `mise exec -- bin/ci` erfolgreich ausführen. Neu hinzugekommene Migrationen werden vor weiteren Tests angewendet.
- Erfolgreiche Starts und Migrationen gegen die jeweils richtigen Datenbanken; kein Staging-Zugriff auf Produktionsdaten oder das Produktionsvolume.
- Funktionsfähige gemeinsame Event-/Medienbeziehung innerhalb jeder Umgebung und keine Verbindung über die Umgebungsgrenze.
- Nachweis, dass Staging keine echten Nachrichten, Newsletter, Kontakt-Synchronisationen oder Social-Media-Veröffentlichungen auslöst und keine automatischen kostenpflichtigen Läufe startet.
- Passwortschutz und Suchmaschinen-Ausschluss für Staging sowie korrekte Indexierungseinstellungen für Produktion.
- Gültiges HTTPS für alle Zielhosts, sichere kanonische Weiterleitungen ohne Schleifen, richtige App-Zuordnung und keine Vermischung beider Projekte.
- Vorher-/Nachher-Abgleich aller bestehenden Nicht-Web-DNS-Einträge bei Host Europe und STRATO einschließlich Werten, Prioritäten und individuell konfigurierten TTLs; keinerlei Änderungen an diesen Einträgen.
- Nachweis der weiterhin funktionierenden Microsoft-365-Dienste vor und nach der jeweiligen Umschaltung: Mail-DNS einschließlich Autodiscover prüfen und Senden/Empfangen über ein vom Nutzer bereitgestelltes Testpostfach durch den Nutzer beziehungsweise einen dazu ausdrücklich beauftragten Verantwortlichen testen lassen. Zusätzlich benötigte externe Links/Callbacks prüfen.
- Ressourcenprüfung unter repräsentativer Nutzung und während Deployments sowie dokumentierte aktuelle Backups und der überprüfte WordPress-Rückweg.
- Nachvollziehbare Freigabe und Veröffentlichung desselben geprüften Images; keine Veröffentlichung fehlgeschlagener oder ungeprüfter Versionen.

Scheitert eine erforderliche Prüfung, wird nicht umgeschaltet beziehungsweise nicht weiter veröffentlicht. Die Durchführung des öffentlichen Umzugs erfolgt nach Abschluss der Vorbereitung im vereinbarten Umschaltfenster.

## Dokumentation und nächster Schritt

Diese Spezifikation beschreibt das abgestimmte Zielbild und den Ablauf. Sie enthält keine ausgeführten DNS-, Server- oder App-Änderungen. Nach ihrer schriftlichen Durchsicht folgt mit `superpowers:writing-plans` ein ausführbarer Plan mit konkreten Dateien, Befehlen, Reihenfolge, Nachweisen und Rückfallaktionen für beide Repositories. Erst nach Prüfung dieses Plans und Auswahl der Ausführungsmethode beginnt die Implementierung.

Technische Grundlagen: [Kamal-Proxy und TLS-Konfiguration](https://kamal-deploy.org/docs/configuration/proxy/), [Kamal-Deployment](https://kamal-deploy.org/docs/commands/deploy/), [Let's-Encrypt-Verifizierung](https://letsencrypt.org/docs/challenge-types/), [GitHub-Actions-Deployments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/control-deployments), [WordPress-URLs und Migration](https://developer.wordpress.org/advanced-administration/upgrade/migrating/).
