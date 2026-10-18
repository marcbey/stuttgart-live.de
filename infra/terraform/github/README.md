# GitHub-Environments und Terraform

Der Stack verwaltet das Environment `production` und ausgewählte nicht-geheime
Variablen für `marcbey/stuttgart-live.de`. Staging und das Russ-Repository werden
durch diesen Stack nicht vollständig eingerichtet. Die gemeinsame Architektur
steht in [INFRA.md](../../../INFRA.md), die aktuellen Secret-Namen und Handgriffe
in der [README](../../../README.md#ci-staging-und-produktionsfreigabe-über-github).

## Verbindliche Produktionsfreigaben

In **beiden** Repositories gelten für `production`:

- erforderliche Reviewer: Marc (`marcbey`) und Katharina Schopper (`kasch0`);
  eine Freigabe reicht, beide haben Repository-Schreibzugriff;
- Selbstfreigaben sind erlaubt, Administrator-Bypass ist ausgeschaltet;
- Deployment-Branch-Policy: ausschließlich Branch `main`.

Diese Schutzregeln sind derzeit über GitHub gesetzt und werden vom
Produktionsworkflow geprüft. **Die Terraform-Ressource bildet sie noch nicht ab.**
Ein `apply` auf das bestehende Environment darf sie nicht entfernen oder ändern.
Vor jeder Anwendung den Plan einschließlich Environment-Regeln prüfen; bei
abweichenden Schutzregeln zuerst die Terraform-Konfiguration vervollständigen.
Nach einer Änderung Reviewer, Selbstfreigabe, Admin-Bypass und Branch-Policy
explizit in GitHub prüfen. Ein neu angelegtes Environment ist ohne diese Regeln
nicht produktionsbereit.

## Nutzung aus der Repository-Wurzel

Voraussetzungen: Terraform `>= 1.8.0` und `GITHUB_TOKEN` mit ausreichenden
Repository-/Environment-Rechten. State und lokale Variablendateien nicht committen.

```bash
cp infra/terraform/github/environments/production/terraform.tfvars.example \
  infra/terraform/github/environments/production/terraform.tfvars
terraform -chdir=infra/terraform/github/environments/production init
terraform -chdir=infra/terraform/github/environments/production plan
```

Erst nach Prüfung der oben genannten Schutzregeln anwenden:

```bash
terraform -chdir=infra/terraform/github/environments/production apply
```

Nicht-geheime Werte wie `SENTRY_ORG` und `SENTRY_PROJECT` können hier verwaltet
werden. Domain, Host-IP und gepinnter SSH-Host-Key kommen aus den versionierten
[Produktions-](../../../config/deploy.hetzner.shared.yml) und
[Staging-Profilen](../../../config/deploy.staging.shared.yml). Sie werden nicht
als zusätzliche Zielkonfiguration in Environment-Variablen gepflegt.

## Secrets getrennt pflegen

Secrets werden separat über GitHub gesetzt, damit sie nicht im Terraform-State
landen. Das vorhandene Skript ist ein **Bootstrap für Stuttgart-Produktion**,
kein vollständiges Setup für Russ, Staging oder die temporären TLS-Secrets.
Es setzt unpräfixierte Produktionsnamen; nicht für Staging verwenden.

Aus der Repository-Wurzel zuerst prüfen:

```bash
mise exec -- script/github_set_production_secrets --dry-run
```

Die lokale `.env` benötigt `OPENAI_API_KEY`, `DB_PASSWORD`,
`KAMAL_REGISTRY_PULL_PASSWORD` und `MEDIA_PROXY_SECRET`; außerdem werden
`config/master.key` und der private Deploy-SSH-Key gelesen. `OPENAI_API_KEY` wird
als Repository-Secret gesetzt, die übrigen Deploy-Werte als Environment-Secrets.
Der Registry-Pull-Token soll nur `read:packages` haben. `SENTRY_AUTH_TOKEN` ist
optional. Das Skript protokolliert Secret-Namen, keine Werte.

Erst nach Prüfung von Repository und Ziel-Environment ohne `--dry-run` starten.
Die vollständigen aktuellen Secret-Listen, einschließlich der ausschließlich
mit `STAGING_` präfixierten Werte, stehen in den READMEs der beiden Anwendungen.
