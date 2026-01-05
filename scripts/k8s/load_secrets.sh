#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${K8S_NAMESPACE:-kafka-clickhouse}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. Install it first (see docs/k8s/README.md)."
  exit 1
fi

if [[ "$#" -lt 1 ]]; then
  echo "Usage:"
  echo "  scripts/k8s/load_secrets.sh --all"
  echo "  scripts/k8s/load_secrets.sh <secret-name> <key>=<file> [key=file...]"
  echo "Example:"
  echo "  scripts/k8s/load_secrets.sh clickhouse-secrets users.xml=secrets/clickhouse/users.xml"
  exit 1
fi

if [[ "$1" == "--all" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  cd "$ROOT_DIR"

  missing_files=()

  require_file() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
      missing_files+=("${path}")
    fi
  }

  require_file "secrets/kafka/client.properties"
  require_file "secrets/kafka/plain-users.json"
  require_file "secrets/kafka/plain-interbroker.txt"
  require_file "secrets/clickhouse/users.xml"

  if [[ "${#missing_files[@]}" -gt 0 ]]; then
    echo "Missing secret files:"
    printf '  - %s\n' "${missing_files[@]}"
    echo "Run scripts/setup/initial_setup.sh and fill in the placeholders first."
    exit 1
  fi

  kubectl create secret generic kafka-plain-users \
    --namespace "${NAMESPACE}" \
    --from-file=plain-users.json=secrets/kafka/plain-users.json \
    --from-file=plain-interbroker.txt=secrets/kafka/plain-interbroker.txt \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic kafka-client-config \
    --namespace "${NAMESPACE}" \
    --from-file=client.properties=secrets/kafka/client.properties \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic clickhouse-secrets \
    --namespace "${NAMESPACE}" \
    --from-file=users.xml=secrets/clickhouse/users.xml \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "Secrets applied in namespace '${NAMESPACE}':"
  echo "  - kafka-plain-users"
  echo "  - kafka-client-config"
  echo "  - clickhouse-secrets"
  exit 0
fi

SECRET_NAME="$1"
shift

FROM_FILE_ARGS=()
for arg in "$@"; do
  if [[ "${arg}" != *=* ]]; then
    echo "Invalid argument: ${arg} (expected key=file)"
    exit 1
  fi
  FROM_FILE_ARGS+=(--from-file="${arg}")
done

kubectl create secret generic "${SECRET_NAME}" \
  --namespace "${NAMESPACE}" \
  "${FROM_FILE_ARGS[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '${SECRET_NAME}' applied in namespace '${NAMESPACE}'."
