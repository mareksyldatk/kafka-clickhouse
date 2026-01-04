#!/usr/bin/env bash
set -euo pipefail

CHART_VERSION="4.14.1"
RELEASE_NAME="ingress-nginx"
NAMESPACE="ingress-nginx"
VALUES_FILE="k8s/values/ingress-nginx-local.yaml"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

echo "Installing ingress-nginx (chart ${CHART_VERSION}) into ${NAMESPACE}..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install "${RELEASE_NAME}" ingress-nginx/ingress-nginx \
  --version "${CHART_VERSION}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE}"

echo "Ingress controller installed. HTTP on 127.0.0.1:30080, HTTPS on 127.0.0.1:30443."
