#!/usr/bin/env bash
set -euo pipefail

CHART_VERSION="0.1351.59"
RELEASE_NAME="confluent-operator"
NAMESPACE="kafka-clickhouse"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

echo "Installing Confluent for Kubernetes operator (chart ${CHART_VERSION}) into ${NAMESPACE}..."
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

helm upgrade --install "${RELEASE_NAME}" confluentinc/confluent-for-kubernetes \
  --version "${CHART_VERSION}" \
  --namespace "${NAMESPACE}" \
  --create-namespace
