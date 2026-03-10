# Ansible für Hetzner App-Host

Dieses Verzeichnis konfiguriert einen frisch provisionierten Hetzner-Server für den Betrieb von `stuttgart-live.de`.

## Voraussetzungen

- Ansible `>= 2.16`
- Collections aus [requirements.yml](/Users/marc/Projects/stuttgart-live.de/infra/ansible/requirements.yml)

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

- [hosts.yml](/Users/marc/Projects/stuttgart-live.de/infra/ansible/inventories/production/hosts.yml)

## Reihenfolge

Zuerst den Basis-Host härten:

```bash
cd infra/ansible
ansible-playbook -i inventories/production/hosts.yml -u root playbooks/bootstrap.yml
```

Dann Docker, PostgreSQL und Backups einrichten:

```bash
ansible-playbook -i inventories/production/hosts.yml -u root playbooks/app_host.yml \
  -e postgres_app_password='starkes-passwort'
```

## Wichtige Variablen

Nicht-sensitive Defaults liegen in:

- [all.yml](/Users/marc/Projects/stuttgart-live.de/infra/ansible/inventories/production/group_vars/all.yml)

Diese Werte solltest du vor dem ersten Lauf prüfen:

- `deploy_user_authorized_keys`
- `postgres_app_password`
- `backup_storage_enabled`
- `backup_storage_source`
