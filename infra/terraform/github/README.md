# GitHub Actions Environment mit Terraform

Dieser Stack verwaltet das GitHub-Environment `production` für `marcbey/stuttgart-live.de`.

Verwaltet wird:

- GitHub Environment

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

Nicht-geheime Hetzner-Zielwerte wie `APP_HOST`, `KAMAL_WEB_HOST` und `KAMAL_SSH_HOST_KEY`
kommen aus der versionierten Datei [config/deploy.hetzner.shared.yml](/Users/marc/Projects/stuttgart-live.de/config/deploy.hetzner.shared.yml).

Dafür gibt es das Skript:

```bash
script/github_set_production_secrets
```

`.env` muss `DB_PASSWORD` und `KAMAL_REGISTRY_PULL_PASSWORD` enthalten.
Dieser Token sollte nur `read:packages` für den Host-Pull auf `ghcr.io` haben.

## Wichtige Hinweise

- Terraform verwaltet hier nur das GitHub-Environment selbst.
- GitHub Actions liest die Hetzner-Zieldaten direkt aus der versionierten Repo-Konfiguration.
