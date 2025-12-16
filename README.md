# Kafka → ClickHouse (Local Pipeline Scaffold)

This repository starts as a minimal scaffold for an incremental Docker Compose–based data pipeline. Services are added one commit at a time; nothing runs yet.

## Repository layout
- `docker-compose.yml` — empty Compose file that will grow with each step.
- `configs/` — mounted configuration files for services (empty placeholder).
- `sql/` — ClickHouse schemas and setup scripts (empty placeholder).
- `scripts/` — helper scripts for local workflows (empty placeholder).

## How to use this scaffold
1) Copy `.env.example` to `.env` when it is introduced; keep secrets out of version control.
2) Add one service or configuration change per commit to keep changes reviewable.
3) Document any new commands or smoke tests in `README.md` as the stack evolves.

## Ground rules
- Prefer mounted configs over baked images.
- Keep stateful services on named volumes once they are added.
- Make startup/verifications explicit with healthchecks and CLI smoke tests as components arrive.
