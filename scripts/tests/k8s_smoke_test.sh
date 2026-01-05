#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

echo "Kubernetes context:"
kubectl config current-context

if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
  echo "Ingress controller pods:"
  kubectl get pods -n ingress-nginx

  echo "Ingress controller service:"
  kubectl get svc -n ingress-nginx

  echo "NodePort reachability (expects 404 or 400 if no Ingress rules yet):"
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:30080/ || true
else
  echo "Ingress namespace not found; skipping ingress checks."
fi

if kubectl get namespace kafka-clickhouse >/dev/null 2>&1; then
  echo "Kafka pods (kafka-clickhouse namespace):"
  kubectl get pods -n kafka-clickhouse || true

  echo "Kafka CRs (kafka-clickhouse namespace):"
  kubectl get kafka -n kafka-clickhouse || true
  kubectl get kraftcontroller -n kafka-clickhouse || true

  if command -v docker >/dev/null 2>&1 && [[ -f /etc/hosts ]] && rg -q "kafka\\.local" /etc/hosts; then
    if command -v nc >/dev/null 2>&1; then
      echo "Kafka NodePort reachability:"
      nc -vz kafka.local 30090 || true
    fi
    echo "Kafka topic list (host-side via NodePort):"
    docker run --rm \
      --add-host kafka.local:host-gateway \
      -v "$(pwd)/secrets/kafka/client.properties:/etc/kafka/client.properties:ro" \
      confluentinc/cp-kafka:8.1.1 \
      kafka-topics \
      --bootstrap-server kafka.local:30090 \
      --command-config /etc/kafka/client.properties \
      --list || true
  fi
fi
