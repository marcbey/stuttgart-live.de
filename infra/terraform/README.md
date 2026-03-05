# AWS Infra with Terraform + Kamal

This folder provisions the AWS infrastructure for `stuttgart-live.de` and provides the values needed for Kamal deploys.

## Prerequisites

- Terraform >= 1.6
- AWS CLI v2
- Kamal (`bin/kamal`)
- AWS SSO profile configured and working:

```bash
aws sso login --profile stgt-live-admin
aws sts get-caller-identity --profile stgt-live-admin
```

## Layout

- `bootstrap/`: one-time remote state resources (S3 + DynamoDB lock table)
- `environments/prod/`: production stack
- `modules/`: reusable infrastructure modules

## 1) Bootstrap remote Terraform state

```bash
cd infra/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit bucket name to be globally unique
terraform init
terraform apply
```

Use the resulting bucket/table values in `environments/prod/backend.hcl`.

## 2) Provision production stack

```bash
cd ../environments/prod
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
```

Create or reuse an EC2 key pair for Kamal SSH:

```bash
aws ec2 create-key-pair \
  --profile stgt-live-admin \
  --region eu-central-1 \
  --key-name stgt-live-prod \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/stgt-live-prod.pem

chmod 600 ~/.ssh/stgt-live-prod.pem
```

Before apply, set DB password in your shell:

```bash
export TF_VAR_db_password='your-strong-db-password'
```

Initialize and apply:

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## 3) Prepare Kamal values from Terraform outputs

Run in `infra/terraform/environments/prod`:

```bash
export KAMAL_WEB_HOST="$(terraform output -raw app_public_ip)"
export KAMAL_REGISTRY_SERVER="$(terraform output -raw ecr_registry_server)"
export AWS_S3_BUCKET="$(terraform output -raw uploads_bucket_name)"
export DB_HOST="$(terraform output -raw db_host)"
export DB_PORT="$(terraform output -raw db_port)"
export AWS_REGION="eu-central-1"
```

Set image and app host explicitly:

```bash
export KAMAL_IMAGE="stgt-live-prod"
export APP_HOST="live.stuttgart-live.de"
export DB_NAME="stuttgart_live_de_production"
export DB_USER="stuttgart_live_de"
export KAMAL_SSH_KEY_PATH="$HOME/.ssh/stgt-live-prod.pem"
```

Or generate most exports automatically:

```bash
eval "$(script/infra_export_kamal_env.sh)"
```

## 4) Configure Kamal secrets

```bash
cd ../../../
cp .kamal/secrets.production.example .kamal/secrets.production
# edit DB_PASSWORD in .kamal/secrets.production
```

## 5) Deploy with Kamal

```bash
bin/kamal setup -d production
bin/kamal deploy -d production
```

## Notes

- The app host is an EC2 instance with Docker preinstalled via user-data.
- EC2 gets IAM access to the uploads S3 bucket (no AWS access keys needed in app env).
- Production Active Storage is configured to use S3 (`config/environments/production.rb` + `config/storage.yml`).
- Restrict `allowed_ssh_cidrs` in `terraform.tfvars` to your static IP(s).
