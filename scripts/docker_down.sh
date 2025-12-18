#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/docker_down.sh [--remove_volumes]

Stops the stack (Kafka + Schema Registry + ClickHouse).
  --remove_volumes  Remove named and anonymous volumes created by Compose.
USAGE
}

remove_volumes=false

case "${1:-}" in
  --remove_volumes)
    remove_volumes=true
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

if $remove_volumes; then
  docker compose down -v
else
  docker compose down
fi
