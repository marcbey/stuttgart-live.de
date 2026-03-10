# Hetzner Infra mit Terraform

Dieses Verzeichnis enthält den neuen Hetzner-Stack für `stuttgart-live.de`.

## Voraussetzungen

- Terraform `>= 1.6`
- Hetzner Cloud API-Token
- vorhandener öffentlicher SSH-Key

## Layout

- `environments/prod/`: produktiver Hetzner-Stack
- `modules/ssh_key/`: SSH-Key-Registrierung
- `modules/firewall/`: Firewall-Regeln
- `modules/app_server/`: Server, Primary IPs und optionales Volume

## Schnellstart

```bash
cd infra/terraform/hetzner/environments/prod
cp terraform.tfvars.example terraform.tfvars
```

Danach `terraform.tfvars` anpassen und das Token setzen:

```bash
export HCLOUD_TOKEN="..."
terraform init
terraform plan
terraform apply
```

## Wichtige Outputs

Nach dem Apply stehen unter anderem diese Werte bereit:

- `server_name`
- `server_ipv4`
- `server_ipv6`
- `app_domain`

Für Ansible kann daraus ein Inventory erzeugt werden:

```bash
script/render_hetzner_inventory.sh
```

Das schreibt standardmäßig nach:

- [hosts.yml](/Users/marc/Projects/stuttgart-live.de/infra/ansible/inventories/production/hosts.yml)

## Hinweise

- `enable_ipv4` ist standardmäßig aktiviert, damit die App problemlos per IPv4 erreichbar bleibt.
- `enable_ipv6` ist zusätzlich aktiviert.
- Das Root-Dateisystem liegt zunächst auf dem Server selbst. Ein zusätzliches Hetzner-Volume ist optional und standardmäßig deaktiviert.
