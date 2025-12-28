#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "Missing .env. Copy .env.example to .env and fill in values." >&2
  return 1
fi

set +u
set -a
# Export vars from .env for the current shell.
# shellcheck disable=SC1091
source .env
set +a
