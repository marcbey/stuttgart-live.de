# GitHub Actions Environment mit Terraform

Dieser Stack verwaltet das GitHub-Environment `production` für `marcbey/stuttgart-live.de`.

Verwaltet werden:

- GitHub Environment
- Environment Variables
  - `APP_HOST`
  - `KAMAL_WEB_HOST`
  - `KAMAL_SSH_HOST_KEY`

## Voraussetzungen

- `GITHUB_TOKEN` mit ausreichenden Rechten auf das Repository

## Nutzung

```bash
cd infra/terraform/github/environments/production
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Die sensiblen GitHub-Environment-Secrets werden bewusst nicht per Terraform verwaltet.
Sie werden separat mit `gh secret set` gesetzt, damit sie nicht im Terraform-State landen.

Dafür gibt es das Skript:

```bash
script/github_set_production_secrets
```

`.env` muss `KAMAL_REGISTRY_PULL_PASSWORD` enthalten.
Dieser Token sollte nur `read:packages` für den Host-Pull auf `ghcr.io` haben.

## Wichtige Hinweise

- Terraform verwaltet hier nur das Environment und nicht-sensitive Variablen.
- `KAMAL_SSH_HOST_KEY` pinnt den erwarteten SSH-Host-Key des Hetzner-Servers für GitHub Actions.
