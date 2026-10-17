# Domainumzug und Staging betreiben

Beide Rails-Apps bleiben auf Hetzner `46.225.224.194`. Stuttgart wird unter
`https://stuttgart-live.de`, Russ unter `https://russ-live.de` veröffentlicht.
Die jeweilige `www`-Adresse erhält HTTPS und leitet mit Status 308, erhaltenem
Pfad und Querystring zum Apex weiter. Die getrennten Testumgebungen liegen unter
`staging.stuttgart-live.de` und `staging.russ-live.de`.

Host Europe verwaltet Stuttgart, STRATO Russ. Codex bedient dafür die vom Nutzer
bereits angemeldeten Browsersitzungen. Der Nutzer hat den öffentlichen Wechsel
für den 17. Oktober 2026 freigegeben. Russ wird zuerst umgestellt;
Stuttgart folgt erst nach vollständiger Russ-Abnahme. Der genaue Abnahmezeitpunkt
und die freigegebenen Release-IDs stehen im privaten Betriebsprotokoll.

## Unveränderliche Daten und Rückweg

MX, SPF, DKIM, DMARC, Autodiscover, SRV, unbekannte Einträge, VPN, Nameserver,
DNSSEC und bestehende CAA-Regeln bleiben einschließlich Prioritäten und TTLs
erhalten. Keine Zone zurücksetzen, keine globalen TTLs absenken und keine
Mail-/Domain-Assistenten verwenden. Insbesondere die Microsoft-365-Konfiguration
und die vorhandenen Mailjet-Verifizierungen werden nicht verändert. Die technische
Abnahme vergleicht sämtliche bestehenden Einträge vor und nach jedem Eingriff.
Der Nutzer kann keine Postfachprobe durchführen; diese ist daher keine Voraussetzung.
Senden und Empfangen werden nicht Ende zu Ende geprüft oder als nachgewiesen bezeichnet.

Es gibt keine `old.*`-Subdomains. Das bisherige WordPress-Hosting bleibt mindestens
72 Stunden nach erfolgreicher Stuttgart-Abnahme unverändert. Für internes
Nachschlagen genügt vorübergehend diese lokale hosts-Zeile:

```text
83.169.28.13 stuttgart-live.de www.stuttgart-live.de
```

Dabei weiterhin `https://stuttgart-live.de` öffnen; eine reine IP-Adresse ersetzt
Hostname und TLS-Zertifikat nicht. Vor dem Livegang Erreichbarkeit und
Zertifikatslaufzeit mit `curl --resolve` erneut prüfen. Hosts-Zuordnung nach dem
Nachschlagen entfernen, damit öffentliche Abnahme und Alltag das echte DNS nutzen.
Die Abschaltung von WordPress braucht den bisherigen Betreiber; dessen Kontakt
und Hostingzugang liegen nicht vor. Eine vollständige WordPress-Sicherung ist
daher nicht zugesagt.

Die alten schopp3r-Adressen müssen nach Nutzerentscheidung nicht erreichbar
bleiben. Ihre Zone und SANs sind für diesen Ablauf nicht erforderlich.
`www.michaelrussgmbh.de` bleibt zunächst unverändert; dessen spätere Weiterleitung
auf Russ ist ein eigener Schritt.

## Vollständiger DNS-Nachweis vor jedem Eingriff

Private Unterlagen liegen ausschließlich unter dem ignorierten Verzeichnis
`tmp/domain-migration/<laufkennung>/`, Verzeichnisrechte `0700`, Dateien `0600`.
Provideransichten oder Exporte **unmittelbar vor jeder Änderung neu erfassen**.
Die Bestandsaufnahme vom 17. Oktober ersetzt diese frische Sicherung nicht.

Bei Host Europe die gesamte aktive Zone als CSV exportieren. Bei STRATO alle
DNS-Ansichten, benutzerdefinierten Zeilen, Weiterleitungsschalter, Standardwerte
und sämtliche bestehenden Subdomains einschließlich VPN erfassen. Die private
STRATO-Datei hat diese Struktur:

```json
{
  "zone": "russ-live.de",
  "inventory_complete": true,
  "records": [
    {"name": "russ-live.de", "type": "MX", "value": "example.invalid.", "priority": 20}
  ],
  "controls": {
    "existing_subdomains": ["vpn.russ-live.de"],
    "redirect": "tatsächlich beobachtete Einstellung",
    "vpn": {"A": "tatsächlich beobachteter Wert"}
  }
}
```

Das verkürzte Beispiel ist kein vollständiges Inventar. `records` enthält alle
benutzerdefinierten Zeilen, `controls` die vollständig gelesenen Einstellungen;
`inventory_complete` erst danach setzen. Unbekannte Selektoren gehören mit hinein.
TTL oder Priorität, die das Portal ausweist, ebenfalls erfassen. Die Normalisierung
ergänzt autoritative Antworten für alle erfassten Namen und Standard-/Webnamen.
Implizite STRATO-MX-Antworten können auch an noch unbenutzten Namen vorhanden sein.

Aus dem Stuttgart-Checkout, mit eigenen Dateinamen je Zeitpunkt und Nameserver:

```bash
mise exec -- bin/dns-inventory --zone stuttgart-live.de --provider hosteurope \
  --provider-file /privat/hosteurope.csv --server ns27.domaincontrol.com \
  --output /privat/stuttgart-before.json
mise exec -- bin/dns-inventory --zone russ-live.de --provider strato \
  --provider-file /privat/strato.json --server docks07.rzone.de \
  --output /privat/russ-before.json
```

Die jeweils zweite Autorität ebenfalls prüfen: `ns28.domaincontrol.com` und
`shades02.rzone.de`. Beide müssen denselben vorgesehenen Zustand liefern.
Das Tool gleicht jede Providerzeile ab, verarbeitet auch das gepackte
Host-Europe-SRV-Format und bewahrt TXT-Werte als zusammengefügte Zeichenfolge.
Fehlerhafte oder nicht autoritative Antworten stoppen den Nachweis.

Für **einen** bevorstehenden Eingriff eine private Erlaubnisdatei erstellen:

```json
{
  "zone": "stuttgart-live.de",
  "operator": "Codex in angemeldeter Providersitzung; technische Web-/DNS-Abnahme",
  "changes": [
    {"action": "add", "record": {"name": "staging.stuttgart-live.de", "type": "A", "value": "46.225.224.194", "priority": null, "ttl": 600}}
  ],
  "provider_control_changes": []
}
```

Ersetzungen sind eine exakte `remove`- und `add`-Änderung einschließlich TTL und
Priorität. Eine eigene ACME-TXT-Änderung braucht zusätzlich
`"owned_acme_value": true`; den tatsächlich hinzugefügten Token privat protokollieren.
Vorhandene fremde Tokens bleiben erhalten. Später nur die eigenen Werte entfernen.
Eine Provideränderung wird mit `key`, `before`, `after` einzeln dokumentiert;
zulässig sind nur die Webschalter `ipv4`, `ipv6`, `redirect` und das Hinzufügen
der eigenen Staging-Subdomain. VPN-Einstellungen sind unveränderlich.

Nach dem Speichern wieder die vollständige Provideransicht erfassen, normalisieren
und gegen den Vorzustand prüfen:

```bash
mise exec -- bin/dns-audit --before /privat/before.json --after /privat/after.json \
  --allow /privat/allow.json --report /privat/audit.json
```

Nur Exit 0 gilt als Erfolg. Der Bericht bindet alle drei Eingaben per SHA256.
SOA-Seriennummern dürfen wechseln; andere SOA-Werte und TTLs bleiben geschützt.
STRATO kann für unkonfigurierte Namen MX-Antworten aus einem Wildcard-Eintrag
ableiten. Eine neue Subdomain verändert, wo diese Synthese greift
([RFC 4592, Abschnitt 3.3.1](https://www.rfc-editor.org/rfc/rfc4592.html#section-3.3.1)).
Solche Antworten nur dann auf den echten Wildcard-Datensatz zurückführen, wenn
vollständige Provideransichten und beide Nameserver die unveränderte Quelle und
das Fehlen separat konfigurierter Einträge belegen. Rohaufnahmen, ihre Hashes und
die einzelnen abgeleiteten Antworten im normalisierten Inventar festhalten.
Keine MX-Ausnahme in die Änderungsliste aufnehmen; bei unklarer Herkunft anhalten.
Bei unerlaubten Nebenwirkungen anhalten und ausschließlich die selbst verursachte
Änderung gezielt rückgängig machen. Kein vollständiger Zonenimport als Rückfall.

## Staging zuerst bereitstellen

1. Beide Vorbereitungsbranches gemeinsam prüfen. Vor jedem Push Remote-Stand
   holen, per Fast-Forward oder Rebase aktualisieren, neue Migrationen lokal
   anwenden und `mise exec -- bin/ci` erneut erfolgreich ausführen.
2. Eigene Staging-Credentials, Session-Schlüssel und DB-Passwörter erzeugen.
   Der Media-Proxy-Schlüssel ist innerhalb des Staging-Paars gleich, gegenüber
   Produktion verschieden. GitHub-Environments `staging` und `production` trennen;
   die vollständigen Secret-Namen stehen in den jeweiligen READMEs.
3. Den separaten Ansible-Staging-Lauf gemäß
   [Infrastruktur-Anleitung](../../infra/ansible/README.md) erst prüfen, dann
   ausführen. Produktionsrollen, Datenbanken und Medienvolume vorher/nachher
   vergleichen. Kein PostgreSQL-Neustart für neue HBA-Regeln.
4. Aktuelle fachliche DB- und Medienbackups außerhalb der App-Ressourcen sichern
   und ihre Wiederherstellbarkeit prüfen. Geprüfte Bootstrap-Images mit festen
   Digests bauen; sie sind noch keine Produktionsfreigabe.
5. Mailpit starten. Nach [README](../../README.md) ein privates Manifest aus
   `config/staging-refresh.example.json` und die root-eigenen Dateien unter
   `/etc/live-staging/` erstellen. Erst Dry-Run, danach denselben Aufruf mit
   `--execute` ausführen. Der Refresh stoppt Staging, kopiert und bereinigt beide
   Fachdatenbanken, leert Operational-Datenbanken und setzt Readiness erst zuletzt.
6. Im tatsächlichen Stage-Container je App
   `bin/rails runner script/ops/check_staging_acl.rb` ausführen. Shared Reader,
   eigene Schreibrechte und Ausschluss aller Produktions-DBs müssen bestehen.
   Erst danach Stage-Web/Jobs starten. Alle Ruby-Aufrufe lokal über `mise`.
7. Ausschließlich die neuen Staging-A-Einträge ergänzen und DNS-Abgleich bestehen
   lassen. HTTPS, unauthentifiziert 401, öffentlicher exakter `/up` mit 200,
   noindex/no-store, Login, Medien und gemeinsame Freigaben testen.
8. Mailpit über `ssh -N -L 8025:127.0.0.1:8025 deploy@46.225.224.194` lokal
   öffnen. Testmail muss nur dort ankommen. Externe APIs und automatische
   Import-/Newsletter-/Social-/KI-Läufe bleiben gesperrt.
9. Beide Stage-Paare und einen rollenden Deploy beobachten: keine OOM-Ereignisse,
   mindestens 1 GiB verfügbarer RAM und 10 GiB freier Speicher nach Kopie;
   PostgreSQL-Verbindungen ausreichend unter dem Limit. Sonst Staging reduzieren
   oder stoppen und neu prüfen. Produktion hat Vorrang.
10. Erst dann Änderungen koordiniert nach `main` übernehmen. Reguläre CI und
    automatische Staging-Läufe beider Apps abnehmen. Diese Images manuell auf
    die bisherigen Produktionsziele im Modus `legacy` freigeben und den neuen
    Veröffentlichungsweg praktisch bestätigen.

## HTTPS vorbereiten und öffentlich umschalten

Für beide Domains einzeln vorgehen. CAA nur lesen. Per DNS-01 ein vorläufiges
Zertifikat für Apex und `www` ausstellen; ausschließlich eigene neue ACME-Werte
ergänzen und anschließend entfernen. Wenn Rechte oder CAA die Ausstellung
verhindern, diesen Schritt anhalten. Bestehende CAA-/TXT-Werte nicht ersetzen.

Zertifikatskette und privaten Schlüssel als `SSL_CERTIFICATE_PEM` und
`SSL_PRIVATE_KEY_PEM` im GitHub-Environment `production` hinterlegen. Mit
`PRODUCTION_DOMAIN_MODE=prepared` dasselbe geprüfte Image manuell freigeben.
Der Deploy prüft Schlüssel/SANs/Laufzeit und HTTPS vor DNS direkt gegen Hetzner.
Zusätzlich relevante Events, Assets und Medien prüfen, zum Beispiel:

```bash
curl --resolve stuttgart-live.de:443:46.225.224.194 -I https://stuttgart-live.de/
curl --resolve www.stuttgart-live.de:443:46.225.224.194 -I https://www.stuttgart-live.de/
```

Bestehende wichtige WordPress-URLs über den vorhandenen Legacy-Redirect-Ablauf
erfassen und auf echte neue Inhalte abbilden. Kein pauschaler Startseiten-Redirect.
Absenderverifizierung, Newsletter-Drafts, alte Bestätigungs-/Abmeldelinks,
Meta-Callbacks und weitere Domainbindungen vorab prüfen. Falls zusätzliche
Mail-DNS nötig wäre, Mailteil klären; keine SPF-/DKIM-Ergänzung vornehmen.

Für den Umzug am 17. Oktober 2026 bleibt die vorhandene Meta-Konfiguration
zunächst erhalten. Ihr fester OAuth-Rückruf zeigt noch auf die bisherige
schopp3r-Adresse. Neue Meta-Verknüpfungen dürfen nach Nutzerentscheidung warten;
dafür müssen später die erlaubte Rückrufadresse in Meta Developers und die
App-Konfiguration gemeinsam auf die neue Domain umgestellt und geprüft werden.
Vorhandene Veröffentlichungen werden durch diesen Umzugsschritt nicht neu
konfiguriert; eine erfolgreiche neue OAuth-Verknüpfung wird nicht behauptet.

Unmittelbar vor dem vereinbarten Fenster: frische DNS-Sicherung, geprüfte
Image-Digests, beide Versionsnachweise, Rückfallwerte und Verantwortliche
protokollieren. Alle bestehenden Mail-DNS-Einträge einschließlich Autodiscover,
Werten, Prioritäten und TTLs vollständig technisch vergleichen. Nach Nutzerentscheidung
ist keine manuelle Postfachprobe erforderlich. Konkurrierende Deployments und Kampagnen aussetzen.

| Eintrag | Stuttgart | Russ |
| --- | --- | --- |
| Apex A | `46.225.224.194` | `46.225.224.194` |
| `www` CNAME | `stuttgart-live.de` | `russ-live.de` |
| `staging` A | `46.225.224.194` | `46.225.224.194` |
| Alte Web-AAAA | entfernen | entfernen |
| Bisherige externe Weiterleitung | entfällt | bei STRATO deaktivieren |

Nur betroffene Web-TTLs auf 300–600 Sekunden setzen, wenn einzeln möglich.
Vorhandene maximale Web-TTL vor dem Wechsel abwarten; ist nur eine globale
Änderung möglich, nichts absenken. IPv6 wird erst nach gesondertem positivem
Nachweis eingerichtet. Für `www` vorhandene A/AAAA im selben gezielten Schritt
durch CNAME ersetzen; andere CNAMEs bleiben erhalten.

Zuerst Russ: vorbereitetes Image unter gemeinsamer Sperre in `live_preissued`
freigeben, dann Weiterleitung und genau die geplanten Web-DNS-Einträge ändern.
DNS-Abgleich, beide Autoritäten und unabhängige Resolver prüfen. Frischer
HTTP-Client und Browserkontext vermeiden alte 301-Caches. Startseite,
`/unternehmen`, `/referenzen`, `/jobs`, Event, Login und Medien abnehmen.
`www` muss mit 308 und erhaltenem Pfad/Query zum Apex führen; keine Schleifen.
Sämtliche bestehenden Mail-DNS-Einträge einschließlich Autodiscover, Werten,
Prioritäten und TTLs erneut vollständig vergleichen.

Erst nach Russ-Abnahme denselben Ablauf für Stuttgart durchführen. Vorher den
Stuttgart-Nachweis durch einen regulären Main-CI-/Staging-Lauf gegen die endgültige
Russ-Produktionsversion erneuern. Ein Nachweis gegen den vorherigen produktiven
Peer reicht für die nächste Freigabe nicht aus. Bei der Profilfolge
`prepared` → `live_preissued` → `live` bleiben Image und Peer dann unverändert.
Kein Image während der Produktionsfreigabe neu bauen und keinen identischen
Commit erneut unter einem bereits bewiesenen SHA-Tag veröffentlichen.

Den WordPress-Rückweg erneut prüfen. Stuttgart-Startseite, Events, Login, Medien,
Legacy-Weiterleitungen, Indexierung und Mailfunktionen abnehmen. Erfolgszeitpunkt
für das mindestens 72-stündige WordPress-Rückfallfenster festhalten.

Bei STRATO deaktiviert ein eigener A-Record die bisherige externe Weiterleitung.
Im tatsächlichen Kunden-Login danach kontrollieren, dass der Menüpunkt inaktiv
ist. Zusätzlich beide Autoritäten auf den neuen A-Record, den entfallenen alten
Web-AAAA und den unveränderten `www`-CNAME prüfen; die Anzeige allein ersetzt
keinen vollständigen DNS-Abgleich. Mail, Autodiscover und VPN bleiben unverändert.

Der bisherige Stuttgart-Apex-AAAA hat eine TTL von 24 Stunden. Der Nutzer
akzeptiert deshalb vorübergehend noch die WordPress-Ansicht aus DNS-Caches.
Das gültige Übergangszertifikat auf Hetzner bleibt aktiv, bis auch der alte
AAAA nicht mehr aufgelöst wird. Eine vorzeitige automatische TLS-Übernahme kann
die ACME-Prüfung noch zum alten IPv6-Webserver schicken.

Nach bestätigter DNS-Propagation `PRODUCTION_DOMAIN_MODE=live` setzen und denselben
freigegebenen Digest erneut deployen. Automatisches TLS einschließlich
Zertifikatskette und Erneuerung prüfen; die Übergangszertifikate anschließend
aus den Production-Secrets entfernen. Kein dauerhaft manueller Zertifikatsbetrieb.

## Unterbrochene Host-Operation klären

Die gemeinsame Sperre verwendet zusätzlich das persistente Verzeichnis
`/var/lock/live-deploy/active-operation`. Nur ein sauber abgeschlossener Vorgang
entfernt es per bestätigtem Handshake. Bei SSH-Verlust, fehlgeschlagenem Befehl
oder Refresh-Fehler bleibt es stehen und blockiert jeden neuen Deploy/Refresh,
auch wenn der Betriebssystem-Lock bereits frei ist. Es gibt keine automatische
Freigabe nach Zeitablauf.

Vor Wiederholung beide GitHub-Läufe, verbleibende SSH-/Kamal-/Refresh-Prozesse,
Docker-Ereignisse und Containerzustände prüfen. Sicherstellen, dass die vorherige
Host-Mutation beendet oder gezielt gestoppt ist; laufende Web-/Jobdienste werden
dafür nicht pauschal angehalten. Erst dann die Kennung als Administrator lesen
und ausschließlich die bekannte eigene Operationsmarkierung unter `flock`
entfernen. Im administrativen SSH-Terminal:

```bash
sudo cat /var/lock/live-deploy/active-operation/owner
# OWNER durch die gerade geprüfte Kennung ersetzen, nachdem der alte Vorgang beendet ist:
sudo flock -n /var/lock/live-deploy/global.lock sh -ec \
  'test "$(cat "$1/owner")" = "$2"; rm "$1/owner"; rmdir "$1"' \
  sh /var/lock/live-deploy/active-operation OWNER
```

Ein belegter `flock`, eine andere Kennung oder unerwartete Dateien verhindern
die Freigabe. Keine pauschale Löschung und keine Freigabe nur aufgrund eines
fehlgeschlagenen GitHub-Jobs: ein unabhängiger Remote-Befehl kann noch laufen.

## Rückfall, Abschluss und späterer Alltag

Bei Problemen mit Domainrouting/HTTPS ausschließlich die gespeicherten eigenen
Web-DNS-Werte und gegebenenfalls den eigenen STRATO-Weiterleitungsschalter
wiederherstellen; die Erlaubnisliste dafür als umgekehrte exakte Änderungen
erstellen und erneut auditieren. Ursprüngliche Mail-/Provider-Einstellungen
nicht vollständig importieren. Rails-Datenbanken und Medien bleiben erhalten;
zwischenzeitlich entstandene Daten werden nicht durch alte Sicherungen ersetzt.
Ein App-Rollback erfordert zusätzlich eine kompatible aktuelle Datenbank.

Nach dem Livegang HTTP/TLS, Fehler, Jobs, Mail und Kapazität beobachten.
Produktionsfehler zuerst mit Sentry untersuchen. WordPress erst nach erfolgreichem
Rückfallfenster und Freigabe durch den Nutzer über den bisherigen Betreiber
abschalten lassen. Lokale hosts-Zuordnungen und eigene ACME-Reste entfernen,
Nachweis und verbleibende externe Abhängigkeiten privat dokumentieren.

Im Alltag: grünes `main` → automatisches Staging → inhaltliche Abnahme →
`gh workflow run deploy-production.yml -f staging_run_id=RUN_ID` im jeweiligen
Repository. Produktion erhält exakt das auf Staging geprüfte Image. Ein anderes
produktives Peer-Image braucht einen neuen Kompatibilitätsnachweis. Dabei zählen
Image-Name, Commit und Digest gemeinsam, auch bei gleichem Commit. Destruktive
Schemaänderungen separat planen; die eigene Migration muss zur noch laufenden
App passen. Staging-Daten werden nur über einen ausdrücklich gestarteten,
bereinigten Refresh erneuert und niemals automatisch überschrieben.
