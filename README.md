# Kafka → ClickHouse (Local Pipeline Scaffold)

This repository starts as a minimal scaffold for an incremental Docker Compose–based data pipeline. Services are added one commit at a time; nothing runs yet.

## Repository layout
- `docker-compose.yml` — empty Compose file that will grow with each step.
- `configs/` — mounted configuration files for services (empty placeholder).
- `sql/` — ClickHouse schemas and setup scripts (empty placeholder).
- `scripts/` — helper scripts for local workflows (empty placeholder).

## How to use this scaffold
1) Copy `.env.example` to `.env` and adjust non-secret defaults (container names, ports) to avoid local conflicts.
2) Add one service or configuration change per commit to keep changes reviewable.
3) Document any new commands or smoke tests in `README.md` as the stack evolves.

## Environment file
- Docker Compose automatically loads `.env` at the repo root; use it to keep container names and host ports predictable across restarts.
- The repo commits `.env.example` only; `.env` itself is git-ignored for local overrides.
- Safe values: ports, container names, volume paths, KRaft node IDs/cluster IDs, and other non-secret defaults.
- The sample `KAFKA_KRAFT_CLUSTER_ID` is a deterministic UUID for local use so the broker can format storage automatically; replace it with your own if you want a new cluster identity.
- Keep secrets out of `.env` and this repo; inject them at runtime via your shell, a locally stored untracked file, or a secrets manager.

## Kafka broker (KRaft)
- Role: 
  - single Kafka broker in KRaft mode (no ZooKeeper),
  - image `apache/kafka:4.1.1`,
  - uses `KAFKA_KRAFT_CLUSTER_ID` to format storage if the log directory is empty.
  - config uses the Apache Kafka Docker env var names (`KAFKA_PROCESS_ROLES`, `KAFKA_LISTENERS`, etc.).
- Endpoints: 
  - host listener `localhost:${KAFKA_BROKER_PORT:-9092}` (external clients), 
  - internal `kafka-broker:9093` (in-cluster), 
  - controller `9094`.
- Data: 
  - persisted in a named Docker volume (`kafka_data`) so topics survive restarts;
  - reset state with `docker compose down -v` (removes volumes).
- Run: 
  - `docker compose up -d kafka-broker`
- Health:
  - `docker compose ps` (look for `healthy` in the `STATE` column)
  - `docker inspect "$(docker compose ps -q kafka-broker)" --format '{{json .State.Health}}'` (probe status and last output)
- Smoke test:
  - create topic:  
    `docker compose exec kafka-broker kafka-topics.sh --bootstrap-server kafka-broker:9093 --create --if-not-exists --topic smoke --replication-factor 1 --partitions 1`
  - list topics:  
    `docker compose exec kafka-broker kafka-topics.sh --bootstrap-server kafka-broker:9093 --list`
  - produce (type lines, end with Ctrl+D):  
    `docker compose exec -T kafka-broker kafka-console-producer.sh --bootstrap-server kafka-broker:9093 --topic smoke`
  - consume from the start (exits after reading 10 messages):  
    `docker compose exec -T kafka-broker kafka-console-consumer.sh --bootstrap-server kafka-broker:9093 --topic smoke --from-beginning --max-messages 10`
  - verify persistence (topic survives restart):
    `docker compose restart kafka-broker`
    `docker compose exec kafka-broker kafka-topics.sh --bootstrap-server kafka-broker:9093 --list`

## Ground rules
- Prefer mounted configs over baked images.
- Keep stateful services on named volumes once they are added.
- Make startup/verifications explicit with healthchecks and CLI smoke tests as components arrive.
