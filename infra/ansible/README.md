# Ansible für Hetzner App-Host

Dieses Verzeichnis konfiguriert den gemeinsamen Hetzner-Host für Stuttgart Live
und Russ Live. Die aktuelle Architektur und die Freigaberegeln für Produktion und
Staging stehen in [INFRA.md](../../INFRA.md). Host-Eingriffe sind von den
App-Deployments über GitHub getrennt.

## Voraussetzungen

- Ansible `>= 2.16`
- Collections aus [requirements.yml](requirements.yml)

Installation der Collections:

```bash
cd infra/ansible
ansible-galaxy collection install -r requirements.yml
```

## Inventory

Das Inventory kann aus Terraform-Outputs erzeugt werden:

```bash
script/render_hetzner_inventory.sh
```

Oder manuell gepflegt werden unter:

- [hosts.yml](inventories/production/hosts.yml)

## Reihenfolge

Zuerst den Basis-Host härten:

```bash
cd infra/ansible
ansible-playbook -i inventories/production/hosts.yml -u root playbooks/bootstrap.yml
```

Danach aus der Repository-Wurzel Docker, PostgreSQL und Backups einrichten:

```bash
script/ansible_app_host_production
```

Das Wrapper-Skript liest `DB_PASSWORD` direkt aus `.env` und ruft `app_host.yml`
mit dem gehärteten `admin`-Benutzer und dem Standard-Schlüssel
`~/.ssh/stgt-live-hetzner-admin` auf.

## PostgreSQL-Neustarts nach Paketupdates

Ubuntu führt nach automatischen Bibliotheksupdates über `needrestart` auch
Dienstneustarts aus. Die Base-Rolle stellt deshalb ausschließlich den Neustart
von `postgresql@16-main.service` zurück. Sicherheitsupdates und die übrigen
Neustartregeln bleiben aktiv; ausstehende PostgreSQL-Neustarts werden weiterhin
gemeldet. Die gezielte Konfiguration lässt sich aus der Repository-Wurzel prüfen:

```bash
ANSIBLE_CONFIG=infra/ansible/ansible.cfg ansible-playbook \
  -i infra/ansible/inventories/production/hosts.yml \
  -u admin --private-key ~/.ssh/stgt-live-hetzner-admin \
  infra/ansible/playbooks/bootstrap.yml --tags needrestart --check --diff
```

Zum Anwenden nach der Prüfung `--check --diff` weglassen. Diese beiden Aufgaben
starten keinen Dienst neu. Nach Bibliotheksupdates den ausstehenden DB-Neustart
zeitnah in einem abgestimmten Wartungsfenster nachholen, damit auch der laufende
Prozess die aktualisierten Bibliotheken verwendet. Alle Produktions- und
Staging-Apps teilen diese PostgreSQL-Instanz: konkurrierende Deployments und
Refreshs aussetzen, die gemeinsame Deploy-Sperre halten und anschließend die
Readiness beider Produktionen sowie laufende Jobprozesse prüfen. Ablauf und
Sperren stehen im [Betriebsrunbook](../../docs/operations/domainumzug-und-staging.md).
Die Ausnahme betrifft `needrestart`; PostgreSQL-Paketupdates oder manuelle
Neustarts können den Dienst weiterhin unterbrechen.

## Wichtige Variablen

Nicht-sensitive Defaults liegen in:

- [all.yml](inventories/production/group_vars/all.yml)

Diese Werte solltest du vor dem ersten Lauf prüfen:

- `deploy_user_authorized_keys`
- `postgres_app_password`
- `postgres_russ_live_readonly_password`, wenn `russ-live.de` auf die Stuttgart-Primärdatenbank lesen soll
- `postgres_russ_live_operational_password`, wenn `russ-live.de` eigene Queue-/Cache-/Cable-Datenbanken auf diesem Host nutzt
- `backup_storage_enabled`
- `backup_storage_source`

Die Russ-Live-Werte sind additiv. Ohne beide Passwörter bleibt das bestehende Stuttgart-Setup unverändert; wenn einer der beiden Werte gesetzt ist, müssen beide gesetzt sein.

## Hinweise zum Media-Proxy

Der produktive Media-Proxy läuft bewusst nicht als zusätzlicher Host-Webserver. `kamal-proxy` bleibt TLS- und Routing-Schicht auf dem Host, während `nginx` im App-Container öffentliche `/media/...`-Requests direkt aus dem Docker-Volume `stuttgart_live_de_storage` beantwortet.

Für Backups bleibt deshalb derselbe Storage-Pfad relevant:

- `/var/lib/docker/volumes/stuttgart_live_de_storage/_data`

## Staging getrennt einrichten

Das eigenständige Playbook `playbooks/staging.yml` legt ausschließlich acht
Staging-Datenbanken, drei eingeschränkte Rollen, das Staging-Medienvolume und
die gemeinsame Deploy-Sperre an. Es installiert keine Pakete, ändert keine
Produktionsrollen/-datenbanken und startet PostgreSQL oder den Proxy nicht neu.
Neue HBA-Regeln betreffen ausschließlich die drei Staging-Rollen; ein Reload
aktiviert sie nach erfolgreicher Syntaxprüfung.

Lege eine lokale, nicht versionierte YAML-Datei mit Dateirechten `0600` an.
Sie enthält ausschließlich drei unterschiedliche, mindestens 32 Zeichen lange
Staging-Passwörter: `staging_stuttgart_db_password`, `staging_russ_reader_password`
und `staging_russ_operational_password`. Produktionspasswörter und `.env` werden
für diesen Aufruf nicht übernommen. Die Werte stehen nicht in Prozessargumenten.

```bash
ANSIBLE_CONFIG=infra/ansible/ansible.cfg ansible-playbook \
  -i infra/ansible/inventories/production/hosts.yml \
  infra/ansible/playbooks/staging.yml --syntax-check
script/ansible_app_host_staging --vars-file /geschuetzter/pfad/staging.yml --check
script/ansible_app_host_staging --vars-file /geschuetzter/pfad/staging.yml
```

Check-Modus zeigt Ressourcen und HBA-Änderungen. Grants werden erst beim echten
Lauf nach Anlage der Datenbanken ausgeführt; ihre tatsächliche Wirkung muss nach
der bereinigten Datenübernahme im jeweiligen Staging-Container mit
`bin/rails runner script/ops/check_staging_acl.rb` bestätigt werden. Erst danach
dürfen Web-/Jobprozesse starten. Auch ein späteres Restore muss die Reader-Grants
wiederherstellen und diese Prüfung wiederholen.

Die Sperre liegt unter `/var/lock/live-deploy/global.lock`, ist für beide Projekte
und Umgebungen gemeinsam und wird durch eine offene SSH-/flock-Sitzung gehalten.
Ein tmpfiles-Eintrag stellt das Verzeichnis nach Neustarts wieder her. Automatische
Deployments dürfen den gemeinsamen Kamal-Proxy nicht eigenmächtig neu starten.

Bei unterbrochenen oder fehlgeschlagenen Host-Mutationen bleibt zusätzlich
`/var/lock/live-deploy/active-operation` bestehen. Diese Markierung niemals
pauschal löschen. Diagnose und gezielte Wiederaufnahme stehen im
[Betriebsrunbook](../../docs/operations/domainumzug-und-staging.md#unterbrochene-host-operation-klären).
