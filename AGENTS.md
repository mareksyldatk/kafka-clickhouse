# Repository Guidelines

## Project Structure & Module Organization
- `docker-compose.yml`: starts empty and grows one service at a time; all infra lives here.
- `configs/`, `sql/`, `scripts/`: mountable configs, database DDL, and helper scripts; each keeps runtime changes versioned.
- `docs/`: step-by-step rationale for every planned commit; read the current step before changing infra.
- `README.md`: top-level orientation; update alongside any user-facing change.

## Build, Test, and Development Commands
- `docker compose config`: validate Compose syntax as services are added.
- `docker compose up -d`: bring up the stack for the current step; expect only documented services to start.
- `docker compose logs -f <service>`: tail logs to debug startup and healthchecks.

## Coding Style & Naming Conventions
- YAML: 2-space indent, explicit keys, avoid inline env definitions when secrets are involved.
- Shell scripts: `bash -euo pipefail`, lower_snake_case filenames, keep scripts idempotent for reruns.
- Config files: prefer mounted files under `configs/` over in-line Compose snippets; name by service (`configs/kafka/…`, `configs/clickhouse/…`).

## Testing Guidelines
- Infra tests are manual for now: use documented smoke tests (e.g., Kafka topic create/produce/consume once those services exist).
- Add a short “how to verify” note for any new service or config change; place it in `README.md` or `docs/`.
- Prefer deterministic checks (healthchecks, CLI commands) over ad-hoc manual clicks.

## Commit & Pull Request Guidelines
- Commit scope: one small, reviewable change per commit (align with the step roadmap in `docs/`).
- Messages: `<component>: <change>` (examples: `kafka: add healthcheck`, `connect: persist internal topics`).
- PRs: include what changed, why it matters, and how to verify; link to the step/issue; attach command outputs or screenshots only when they add clarity.

## Security & Configuration Tips
- Keep secrets out of repo: use `.env` only for non-sensitive defaults; mount secret files locally when auth is introduced.
- Prefer explicit ports, topics, and volumes; avoid “magic defaults” so restarts remain predictable.
