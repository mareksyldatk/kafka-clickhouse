#!/usr/bin/env bash
set -euo pipefail

CHART_VERSION="32.4.3"
APP_VERSION="4.0.0"
RELEASE_NAME="kafka"
NAMESPACE="kafka-clickhouse"
VALUES_FILE="k8s/values/kafka.yaml"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

echo "Installing Kafka (chart ${CHART_VERSION}, app ${APP_VERSION}) into ${NAMESPACE}..."
helm upgrade --install "${RELEASE_NAME}" oci://registry-1.docker.io/bitnamicharts/kafka \
  --version "${CHART_VERSION}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE}"
