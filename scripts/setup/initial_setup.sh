#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Create local secrets directories (ignored by git).
mkdir -p secrets/kafka secrets/clickhouse

# Seed local secrets from templates. Do not overwrite secrets/local.env once created.
if [[ ! -f secrets/local.env ]]; then
  cp templates/secrets/local.env secrets/local.env
fi
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
      python - <<'PY' "${template_path}" "${target_path}"
import os
import re
import sys

template_path = sys.argv[1]
target_path = sys.argv[2]

with open(template_path, "r", encoding="utf-8") as fh:
    content = fh.read()

pattern = re.compile(r"\$\{([A-Z0-9_]+)\}")

def repl(match):
    key = match.group(1)
    return os.environ.get(key, match.group(0))

rendered = pattern.sub(repl, content)

with open(target_path, "w", encoding="utf-8") as fh:
    fh.write(rendered)
PY
    fi
  }

  if [[ "${#missing_vars[@]}" -eq 0 ]]; then
  render_template "templates/secrets/kafka/client.properties" "secrets/kafka/client.properties"
  render_template "templates/secrets/kafka/client_jaas.conf" "secrets/kafka/client_jaas.conf"
  render_template "templates/secrets/kafka/broker_jaas.conf" "secrets/kafka/broker_jaas.conf"
  render_template "templates/secrets/kafka/plain-users.json" "secrets/kafka/plain-users.json"
  render_template "templates/secrets/kafka/plain-interbroker.txt" "secrets/kafka/plain-interbroker.txt"
  else
    echo "Skipping Kafka secrets rendering; missing in secrets/local.env:"
    printf '  - %s\n' "${missing_vars[@]}"
  fi
fi

# Final reminder for local-only setup.
echo "Secrets templates copied. Update secrets/local.env with real values."
