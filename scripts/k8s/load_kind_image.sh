#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="kafka-clickhouse"

if ! command -v kind >/dev/null 2>&1; then
  echo "kind not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

if [[ "$#" -lt 1 ]]; then
  echo "Usage: scripts/k8s/load_kind_image.sh <image> [image...]"
  exit 1
fi

kind load docker-image --name "${CLUSTER_NAME}" "$@"
