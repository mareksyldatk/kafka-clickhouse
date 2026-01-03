#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="kafka-clickhouse"

if ! command -v kind >/dev/null 2>&1; then
  echo "kind not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

echo "Deleting kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}"
