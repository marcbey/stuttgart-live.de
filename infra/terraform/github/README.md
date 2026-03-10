# GitHub Actions Environment mit Terraform

Dieser Stack verwaltet das GitHub-Environment `production` für `marcbey/stuttgart-live.de`.

Verwaltet werden:

- GitHub Environment
- Environment Variables
- Environment Secrets für den Kamal-Deploy

Aktuelle Secret-Quellen:

- `.env` im Projekt-Root
- `config/master.key`
- `~/.ssh/stgt-live-hetzner-admin`

## Voraussetzungen

- `GITHUB_TOKEN` mit ausreichenden Rechten auf das Repository
- Zugriff auf `.env`
- Zugriff auf `config/master.key`
- Zugriff auf den privaten SSH-Key für den Deploy

## Nutzung

```bash
cd infra/terraform/github/environments/production
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Wichtige Hinweise

- Der Stack liest Secrets lokal aus Dateien und `.env`.
- Terraform-State ist daher als sensibel zu behandeln.
- Die Pfade in `terraform.tfvars` sollten entweder absolut sein oder relativ zu diesem Verzeichnis.
