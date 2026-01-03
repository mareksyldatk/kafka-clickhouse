#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

CLUSTER_NAME="kafka-clickhouse"
CONFIG_FILE="k8s/kind/cluster.yaml"

if ! command -v kind >/dev/null 2>&1; then
  echo "kind not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

echo "Creating kind cluster '${CLUSTER_NAME}' with config ${CONFIG_FILE}..."
kind create cluster --name "${CLUSTER_NAME}" --config "${CONFIG_FILE}"

echo "Cluster created. Use kubectl context 'kind-${CLUSTER_NAME}'."
