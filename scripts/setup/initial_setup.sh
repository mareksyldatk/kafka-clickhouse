#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Create local secrets directories (ignored by git).
mkdir -p secrets/kafka secrets/clickhouse

# Seed local secrets from templates without overwriting existing files.
cp -n secrets/templates/local.env secrets/local.env
cp -n secrets/templates/kafka/* secrets/kafka/

# Final reminder for local-only setup.
echo "Secrets templates copied. Update secrets/local.env with real values."
