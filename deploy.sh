#!/usr/bin/env bash
set -euo pipefail

terraform init
terraform apply -auto-approve -var "app_name=${1:-bff-webapp}"