#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

echo "Kubernetes context:"
kubectl config current-context

echo "Ingress controller pods:"
kubectl get pods -n ingress-nginx

echo "Ingress controller service:"
kubectl get svc -n ingress-nginx

echo "NodePort reachability (expects 404 or 400 if no Ingress rules yet):"
curl -sS -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:30080/ || true
