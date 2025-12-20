#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # Export vars from .env for downstream tools.
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if ! command -v pyenv >/dev/null 2>&1; then
  echo "pyenv is required to run Python tools. Install it and retry." >&2
  exit 1
fi

eval "$(pyenv init -)"
if [[ "${PYENV_VERSION:-}" != "kafka-clickhouse" && "${VIRTUAL_ENV:-}" != *"/kafka-clickhouse" ]]; then
  pyenv activate kafka-clickhouse
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <tool> [args...]" >&2
  echo "Example: $0 avro_producer.py" >&2
  exit 1
fi

tool="$1"
shift

python "scripts/python/${tool}" "$@"
