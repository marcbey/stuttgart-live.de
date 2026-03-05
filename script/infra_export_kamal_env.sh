#!/usr/bin/env bash
set -euo pipefail

TF_DIR="${1:-infra/terraform/environments/prod}"

if [[ ! -d "$TF_DIR" ]]; then
  echo "Terraform directory not found: $TF_DIR" >&2
  exit 1
fi

cd "$TF_DIR"

echo "export KAMAL_WEB_HOST=\"$(terraform output -raw app_public_ip)\""
echo "export KAMAL_REGISTRY_SERVER=\"$(terraform output -raw ecr_registry_server)\""
echo "export AWS_S3_BUCKET=\"$(terraform output -raw uploads_bucket_name)\""

DB_HOST_VALUE="$(terraform output -raw db_host 2>/dev/null || true)"
DB_PORT_VALUE="$(terraform output -raw db_port 2>/dev/null || true)"

if [[ -n "$DB_HOST_VALUE" ]]; then
  echo "export DB_HOST=\"$DB_HOST_VALUE\""
fi

if [[ -n "$DB_PORT_VALUE" ]]; then
  echo "export DB_PORT=\"$DB_PORT_VALUE\""
fi

echo "export AWS_REGION=\"${AWS_REGION:-eu-central-1}\""
echo "export KAMAL_IMAGE=\"${KAMAL_IMAGE:-stgt-live-prod}\""
