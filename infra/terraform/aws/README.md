# AWS Infra mit Terraform + Kamal

Dieses Verzeichnis provisioniert die AWS-Infrastruktur für `stuttgart-live.de` und stellt die Werte für Kamal-Deploys bereit.

## Voraussetzungen

- Terraform >= 1.6
- AWS CLI v2
- Kamal (`bin/kamal`)
- funktionierendes AWS-SSO-Profil:

```bash
aws sso login --profile stgt-live-admin
aws sts get-caller-identity --profile stgt-live-admin
```

## Struktur

- `bootstrap/`: einmalige Ressourcen für den Remote State (S3 + DynamoDB Lock Table)
- `environments/prod/`: produktiver Stack
- `modules/`: wiederverwendbare Infrastruktur-Module

## 1) Remote Terraform State bootstrappen

```bash
cd infra/terraform/aws/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Bucket-Namen auf global eindeutigen Wert setzen
terraform init
terraform apply
```

Die erzeugten Bucket-/Tabellen-Werte anschließend in `environments/prod/backend.hcl` eintragen.

## 2) Produktions-Stack provisionieren

```bash
cd ../environments/prod
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars anpassen
```

EC2-Key-Pair für Kamal-SSH erzeugen oder wiederverwenden:

```bash
aws ec2 create-key-pair \
  --profile stgt-live-admin \
  --region eu-central-1 \
  --key-name stgt-live-prod \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/stgt-live-prod.pem

chmod 600 ~/.ssh/stgt-live-prod.pem
```

Vor dem Apply das DB-Passwort setzen:

```bash
export TF_VAR_db_password='your-strong-db-password'
```

Für lokale Production-Läufe kann der Wert auch per Wrapper aus
`.kamal/secrets.production` übernommen werden:

```bash
script/terraform_prod plan
script/terraform_prod apply -auto-approve
```

Initialisieren und anwenden:

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## 3) Kamal-Werte aus Terraform-Outputs ableiten

Ausführen in `infra/terraform/aws/environments/prod`:

```bash
export KAMAL_WEB_HOST="$(terraform output -raw app_public_ip)"
export KAMAL_REGISTRY_SERVER="$(terraform output -raw ecr_registry_server)"
export AWS_S3_BUCKET="$(terraform output -raw uploads_bucket_name)"
export DB_HOST="$(terraform output -raw db_host)"
export DB_PORT="$(terraform output -raw db_port)"
export AWS_REGION="eu-central-1"
```

Image und App-Host explizit setzen:

```bash
export KAMAL_IMAGE="stgt-live-prod"
export APP_HOST="live.stuttgart-live.de"
export DB_NAME="stuttgart_live_de_production"
export DB_USER="stuttgart_live_de"
export KAMAL_SSH_KEY_PATH="$HOME/.ssh/stgt-live-prod.pem"
```

Alternativ die meisten Exports automatisch erzeugen:

```bash
eval "$(script/infra_export_kamal_env.sh)"
```

## 4) Kamal-Secrets konfigurieren

```bash
cd ../../../
cp .kamal/secrets.production.example .kamal/secrets.production
# DB_PASSWORD in .kamal/secrets.production setzen
```

## 5) Mit Kamal deployen

```bash
bin/kamal setup -d production
bin/kamal deploy -d production
```

## Hinweise

- Der App-Host ist eine EC2-Instanz mit per User Data vorbereitetem Docker.
- EC2 erhält IAM-Zugriff auf den Uploads-S3-Bucket, daher sind keine AWS-Access-Keys in der App-Umgebung nötig.
- Production Active Storage ist auf S3 konfiguriert (`config/environments/production.rb` + `config/storage.yml`).
- `allowed_ssh_cidrs` in `terraform.tfvars` auf feste eigene IPs begrenzen.
