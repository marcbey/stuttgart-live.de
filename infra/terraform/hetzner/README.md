# Hetzner Infra mit Terraform

Dieses Verzeichnis provisioniert den gemeinsamen Hetzner-Host für Stuttgart Live
und Russ Live einschließlich Produktion und Staging. Staging erhält keinen
eigenen Server. Der aktuelle Betrieb und die Trennung der Ressourcen stehen in
[INFRA.md](../../../INFRA.md); diese Anleitung betrifft Infrastrukturänderungen.

## Voraussetzungen

- Terraform `>= 1.6`
- Hetzner Cloud API-Token
- vorhandener öffentlicher SSH-Key

## Layout

- `environments/prod/`: produktiver Hetzner-Stack
- `modules/ssh_key/`: SSH-Key-Registrierung
- `modules/firewall/`: Firewall-Regeln
- `modules/app_server/`: Server, Primary IPs und optionales Volume

## Nutzung aus der Repository-Wurzel

```bash
cp infra/terraform/hetzner/environments/prod/terraform.tfvars.example \
  infra/terraform/hetzner/environments/prod/terraform.tfvars
```

Danach `terraform.tfvars` anpassen und das Token setzen:

```bash
export HCLOUD_TOKEN="..."
terraform -chdir=infra/terraform/hetzner/environments/prod init
terraform -chdir=infra/terraform/hetzner/environments/prod plan
# Erst nach Abgleich mit dem bestehenden Host und Prüfung des Plans:
terraform -chdir=infra/terraform/hetzner/environments/prod apply
```

## Wichtige Outputs

Nach dem Apply stehen unter anderem diese Werte bereit:

- `server_name`
- `server_ipv4`
- `server_ipv6`
- `app_domain`

`app_domain` ist ein historischer Terraform-Ausgabewert und steuert weder DNS
noch das aktuelle Kamal-Ziel. Maßgeblich sind die versionierten
[Produktions-](../../../config/deploy.hetzner.shared.yml) und
[Staging-Profile](../../../config/deploy.staging.shared.yml) sowie
`PRODUCTION_DOMAIN_MODE` im GitHub-Environment.

Für Ansible kann daraus aus der Repository-Wurzel ein Inventory erzeugt werden.
Das überschreibt das bestehende Inventory; den Diff vor einem Ansible-Lauf prüfen:

```bash
script/render_hetzner_inventory.sh
```

Das schreibt standardmäßig nach:

- [hosts.yml](../../ansible/inventories/production/hosts.yml)

## Hinweise

- `enable_ipv4` ist standardmäßig aktiviert, damit die App problemlos per IPv4 erreichbar bleibt.
- `enable_ipv6` ist zusätzlich aktiviert.
- Das Root-Dateisystem liegt zunächst auf dem Server selbst. Ein zusätzliches Hetzner-Volume ist optional und standardmäßig deaktiviert.
- Der Produktions-Media-Proxy für öffentliche Bilder benötigt keine zusätzliche Hetzner-Ressource. Die Dateien liegen weiter im bestehenden Docker-/Kamal-Volume für `/rails/storage`.
