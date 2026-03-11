#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${1:-$ROOT_DIR/infra/terraform/hetzner/environments/prod}"
OUTPUT_FILE="${2:-$ROOT_DIR/infra/ansible/inventories/production/hosts.yml}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq ist erforderlich." >&2
  exit 1
fi

# Das Inventory wird direkt aus Terraform-Outputs gebaut, damit Hostname und IP
# nicht separat in Ansible gepflegt werden müssen.
OUTPUT_JSON="$(terraform -chdir="$TF_DIR" output -json)"
SERVER_NAME="$(jq -r '.server_name.value' <<<"$OUTPUT_JSON")"
SERVER_IPV4="$(jq -r '.server_ipv4.value // empty' <<<"$OUTPUT_JSON")"
SERVER_IPV6="$(jq -r '.server_ipv6.value // empty' <<<"$OUTPUT_JSON")"

ANSIBLE_HOST="$SERVER_IPV4"
if [[ -z "$ANSIBLE_HOST" ]]; then
  # IPv6 bleibt ein Fallback, falls bewusst ohne öffentliche IPv4 gearbeitet wird.
  ANSIBLE_HOST="$SERVER_IPV6"
fi

if [[ -z "$ANSIBLE_HOST" ]]; then
  echo "Es wurde weder eine IPv4- noch eine IPv6-Adresse aus Terraform-Outputs gelesen." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

cat >"$OUTPUT_FILE" <<EOF
all:
  children:
    production:
      hosts:
        $SERVER_NAME:
          ansible_host: $ANSIBLE_HOST
EOF

echo "Inventory geschrieben: $OUTPUT_FILE"
