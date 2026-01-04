#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Create local secrets directories (ignored by git).
mkdir -p secrets/kafka secrets/clickhouse

# Seed local secrets from templates (overwrite to keep in sync).
cp templates/secrets/local.env secrets/local.env
cp templates/secrets/kafka/* secrets/kafka/
cp templates/secrets/clickhouse/* secrets/clickhouse/

# Render Kafka secret files from secrets/local.env when placeholders are present.
if [[ -f secrets/local.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source secrets/local.env
  set +a

  required_vars=(
    KAFKA_BROKER_SASL_USERNAME
    KAFKA_BROKER_SASL_PASSWORD
    SCHEMA_REGISTRY_SASL_USERNAME
    SCHEMA_REGISTRY_SASL_PASSWORD
    KAFKA_CLIENT_SASL_USERNAME
    KAFKA_CLIENT_SASL_PASSWORD
  )

  missing_vars=()
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing_vars+=("${var}")
    fi
  done

  render_template() {
    local template_path="$1"
    local target_path="$2"
    if [[ ! -f "${template_path}" ]]; then
      return
    fi
    if [[ ! -f "${target_path}" ]] || grep -Eq "\\$\\{(KAFKA|SCHEMA_REGISTRY)_" "${target_path}"; then
      perl -pe 's/\\$\\{([A-Z0-9_]+)\\}/$ENV{$1}/ge' "${template_path}" > "${target_path}"
    fi
  }

  if [[ "${#missing_vars[@]}" -eq 0 ]]; then
    render_template "templates/secrets/kafka/client.properties" "secrets/kafka/client.properties"
    render_template "templates/secrets/kafka/client_jaas.conf" "secrets/kafka/client_jaas.conf"
    render_template "templates/secrets/kafka/broker_jaas.conf" "secrets/kafka/broker_jaas.conf"

    if [[ ! -f secrets/kafka/client-passwords ]] || grep -q "REPLACE_ME" secrets/kafka/client-passwords; then
      printf "%s,%s\n" "${SCHEMA_REGISTRY_SASL_PASSWORD}" "${KAFKA_CLIENT_SASL_PASSWORD}" > secrets/kafka/client-passwords
    fi
    if [[ ! -f secrets/kafka/inter-broker-password ]] || grep -q "REPLACE_ME" secrets/kafka/inter-broker-password; then
      printf "%s\n" "${KAFKA_BROKER_SASL_PASSWORD}" > secrets/kafka/inter-broker-password
    fi
    if [[ ! -f secrets/kafka/controller-password ]] || grep -q "REPLACE_ME" secrets/kafka/controller-password; then
      printf "%s\n" "${KAFKA_BROKER_SASL_PASSWORD}" > secrets/kafka/controller-password
    fi
  else
    echo "Skipping Kafka secrets rendering; missing in secrets/local.env:"
    printf '  - %s\n' "${missing_vars[@]}"
  fi
fi

# Final reminder for local-only setup.
echo "Secrets templates copied. Update secrets/local.env with real values."
