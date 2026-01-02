#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source scripts/source_env.sh

usage() {
  cat <<'USAGE'
Usage: scripts/docker_up.sh [--recreate]

Starts the stack (Kafka + Schema Registry + ClickHouse) in detached mode.
  --recreate  Rebuild images, force-recreate containers, and renew anonymous volumes.
USAGE
}

recreate=false

case "${1:-}" in
  --recreate)
    recreate=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage
    exit 1
    ;;
esac

if $recreate; then
  docker compose up -d --force-recreate --renew-anon-volumes
else
  docker compose up -d
fi
