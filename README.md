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
- Safe values: ports, volume paths, and other non-secret defaults.
- `CLUSTER_ID` is required for KRaft (the broker uses it to format storage on first start); generate one with `docker run --rm confluentinc/cp-kafka:7.7.7 kafka-storage.sh random-uuid`.
- Keep secrets out of `.env` and this repo; inject them at runtime via your shell, a locally stored untracked file, or a secrets manager.

## Helper scripts
- Start the stack: `scripts/docker_up.sh`
- Start with image rebuild + container recreation + fresh anonymous volumes: `scripts/docker_up.sh --recreate`
- Stop the stack: `scripts/docker_down.sh`
- Stop and remove volumes (including anonymous ones): `scripts/docker_down.sh --remove_volumes`

## Kafka broker (KRaft)
- Role: 
  - single Kafka broker in KRaft mode (no ZooKeeper),
  - image `confluentinc/cp-kafka:7.7.7`,
  - uses `CLUSTER_ID` to format storage if the log directory is empty.
  - config uses the `cp-kafka` Docker env var names (`KAFKA_PROCESS_ROLES`, `KAFKA_LISTENERS`, etc.).
- Endpoints: 
  - host listener `localhost:${KAFKA_BROKER_PORT:-9092}` (external clients), 
  - internal `kafka-broker:9093` (in-cluster), 
  - controller `9094`.
- Data: 
  - persisted in a named Docker volume (`kafka_data`) so topics survive restarts;
  - reset state with `docker compose down -v` (removes volumes).
- Volumes visibility:
  - list this project’s named volumes: `docker volume ls --filter label=com.docker.compose.project=<project>`
  - note: some images may create anonymous volumes via Dockerfile `VOLUME`; those won’t appear in `docker-compose.yml` unless we explicitly mount over them.
### Run
- `docker compose up -d kafka-broker`

### Health
- `docker compose ps` (look for `healthy` in the `STATE` column)
- `docker inspect "$(docker compose ps -q kafka-broker)" --format '{{json .State.Health}}'` (probe status and last output)

### Smoke tests
#### Topic lifecycle
- Create the topic (idempotent if it already exists):
```bash
docker compose exec kafka-broker kafka-topics \
  --bootstrap-server kafka-broker:9093 \
  --create \
  --if-not-exists \
  --topic smoke_kafka \
  --replication-factor 1 \
  --partitions 1
```
- List topics (should include `smoke_kafka`):
```bash
docker compose exec kafka-broker kafka-topics --bootstrap-server kafka-broker:9093 --list
```

#### Produce and consume
- Produce (sends lines as messages; end with Ctrl+D):
```bash
docker compose exec -T kafka-broker kafka-console-producer.sh \
  --bootstrap-server kafka-broker:9093 \
  --topic smoke_kafka
```
- Consume from the start (reads historical messages; exits after 10):
```bash
docker compose exec -T kafka-broker kafka-console-consumer.sh \
  --bootstrap-server kafka-broker:9093 \
  --topic smoke_kafka \
  --from-beginning \
  --max-messages 10
```

#### Persistence check
- Restart the broker and list topics again (topic should still exist):
```bash
docker compose restart kafka-broker
docker compose exec kafka-broker kafka-topics --bootstrap-server kafka-broker:9093 --list
```

## Schema Registry
- Role:
  - schema registry service backed by Kafka (stores schemas in an internal Kafka topic),
  - image `confluentinc/cp-schema-registry:7.7.7`,
  - exposed on `http://localhost:8081`.
### Run
- `docker compose up -d schema-registry`

### Smoke tests
#### List subjects
- List registered subjects (empty `[]` if none yet):
  `curl -s http://localhost:8081/subjects`

#### Schema lifecycle (no producers/consumers yet)
- Set subject compatibility to BACKWARD (allows adding fields with defaults):
```bash
curl -s -X PUT -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"compatibility":"BACKWARD"}' \
  http://localhost:8081/config/smoke_avro-value
```
- Register v1 schema (creates the subject):
```bash
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"SmokeAvro\",\"namespace\":\"example\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"}]}"}' \
  http://localhost:8081/subjects/smoke_avro-value/versions
```
- List subject versions (should show `1`):
```bash
curl -s http://localhost:8081/subjects/smoke_avro-value/versions
```
- Print latest schema (full JSON, then the schema string):
```bash
curl -s http://localhost:8081/subjects/smoke_avro-value/versions/latest
curl -s http://localhost:8081/subjects/smoke_avro-value/versions/latest | jq -r .schema
```
- Check compatibility for a candidate schema (adds a field with default = backward compatible):
```bash
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"SmokeAvro\",\"namespace\":\"example\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"source\",\"type\":\"string\",\"default\":\"unknown\"}]}"}' \
  http://localhost:8081/compatibility/subjects/smoke_avro-value/versions/latest
```
- Register v2 schema (extends the subject):
```bash
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"SmokeAvro\",\"namespace\":\"example\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"source\",\"type\":\"string\",\"default\":\"unknown\"}]}"}' \
  http://localhost:8081/subjects/smoke_avro-value/versions
```

#### Avro messages (optional)
- Create the topic for Avro messages:
```bash
docker compose exec kafka-broker kafka-topics \
  --bootstrap-server kafka-broker:9093 \
  --create \
  --if-not-exists \
  --topic smoke_avro \
  --replication-factor 1 \
  --partitions 1
```
- Produce (auto-registers schema under `<topic>-value` and sends Avro):
```bash
docker compose exec -T schema-registry kafka-avro-console-producer \
  --bootstrap-server kafka-broker:9093 \
  --topic smoke_avro \
  --property schema.registry.url=http://schema-registry:8081 \
  --property value.schema='{"type":"record","name":"SmokeAvro","namespace":"example","fields":[{"name":"id","type":"string"}]}'
```
- Type a few records (one per line), then end with Ctrl+D:
```json
{"id":"1"}
```
- Consume (prints decoded Avro records):
```bash
docker compose exec -T schema-registry kafka-avro-console-consumer \
  --bootstrap-server kafka-broker:9093 \
  --topic smoke_avro \
  --from-beginning \
  --property schema.registry.url=http://schema-registry:8081 \
  --max-messages 5
```
- Verify Schema Registry registered the subject:
```bash
curl -s http://localhost:8081/subjects | jq -r '.[]' | rg '^smoke_avro-value$'
```

## Ground rules
- Prefer mounted configs over baked images.
- Keep stateful services on named volumes once they are added.
- Make startup/verifications explicit with healthchecks and CLI smoke tests as components arrive.
