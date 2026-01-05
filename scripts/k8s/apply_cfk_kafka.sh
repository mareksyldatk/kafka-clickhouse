#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

kubectl apply -k k8s/base/confluent
