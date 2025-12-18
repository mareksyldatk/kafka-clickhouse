# Kafka → ClickHouse (Local Pipeline Scaffold)

This repository starts as a minimal scaffold for an incremental Docker Compose–based data pipeline. Services are added one commit at a time; Kafka + Schema Registry are now running.

## Repository layout
- `docker-compose.yml` — Compose stack that grows one service at a time; currently includes Kafka (KRaft) + Schema Registry.
- `configs/` — mounted configuration files for services (empty placeholder).
- `sql/` — ClickHouse schemas and setup scripts (empty placeholder).
- `scripts/` — helper scripts for local workflows (empty placeholder).

## How to use this scaffold
1) Copy `.env.example` to `.env` and set required values (e.g., `CLUSTER_ID`).
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
- Setup Python virtualenv + deps (pyenv required): `scripts/setup_python.sh`

## Cluster topology
```
                 Kafka KRaft Cluster
Controllers:  kafka-controller-1/2/3 (quorum on :9094)
   Brokers:   kafka-broker-1/2/3 (clients on :9093, host :19092/:29092/:39092)
 Schema Reg:  schema-registry (http://localhost:8081)
```

### Broker vs controller split
- Controllers manage cluster metadata and leader elections (KRaft quorum).
- Brokers handle client traffic (produce/consume) and store topic data.
- This split mirrors production patterns while keeping the local stack small.

## Kafka cluster (KRaft)
- Role:
  - three controller-only nodes + three broker-only nodes (no ZooKeeper),
  - image `confluentinc/cp-kafka:7.7.7`,
  - uses `CLUSTER_ID` to format storage if the log directory is empty,
  - config uses the `cp-kafka` Docker env var names (`KAFKA_PROCESS_ROLES`, `KAFKA_LISTENERS`, etc.).
- Endpoints:
  - brokers (host): `localhost:19092`, `localhost:29092`, `localhost:39092`,
  - brokers (in-cluster): `kafka-broker-1:9093`, `kafka-broker-2:9093`, `kafka-broker-3:9093`,
  - controllers (in-cluster): `kafka-controller-1:9094`, `kafka-controller-2:9094`, `kafka-controller-3:9094`.
- Data:
  - brokers and controllers persist state in named Docker volumes (one per node),
  - reset state with `docker compose down -v` (removes volumes).
- Volumes visibility:
  - list this project’s named volumes: `docker volume ls --filter label=com.docker.compose.project=<project>`
  - note: some images may create anonymous volumes via Dockerfile `VOLUME`; those won’t appear in `docker-compose.yml` unless we explicitly mount over them.
### Run
- `docker compose up -d`

### Health
- `docker compose ps` (look for `healthy` in the `STATE` column)
- `docker inspect "$(docker compose ps -q kafka-broker-1)" --format '{{json .State.Health}}'` (probe status and last output)

### Smoke tests
#### Topic lifecycle
- Create the topic (idempotent if it already exists):
```bash
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --create \
  --if-not-exists \
  --topic smoke_kafka \
  --replication-factor 3 \
  --partitions 1
```
- List topics (should include `smoke_kafka`):
```bash
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --list
```

#### Produce and consume
- Produce (sends lines as messages; end with Ctrl+D):
```bash
docker compose exec -T kafka-broker-1 kafka-console-producer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --topic smoke_kafka
```
- Consume from the start (reads historical messages; exits after 10):
```bash
docker compose exec -T kafka-broker-1 kafka-console-consumer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --topic smoke_kafka \
  --from-beginning \
  --max-messages 10
```

#### Persistence check
- Restart the broker and list topics again (topic should still exist):
```bash
docker compose restart kafka-broker-1
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --list
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
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --create \
  --if-not-exists \
  --topic smoke_avro \
  --replication-factor 3 \
  --partitions 1
```
- Produce (auto-registers schema under `<topic>-value` and sends Avro):
```bash
docker compose exec -T schema-registry kafka-avro-console-producer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
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
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --topic smoke_avro \
  --from-beginning \
  --property schema.registry.url=http://schema-registry:8081 \
  --max-messages 5
```
- Verify Schema Registry registered the subject:
```bash
curl -s http://localhost:8081/subjects | jq -r '.[]' | rg '^smoke_avro-value$'
```

## Python Avro producer
### Setup
- Create a pyenv virtualenv and install dependencies:
```bash
scripts/setup_python.sh
pyenv activate kafka-clickhouse
```

### Run
- Produce a single Avro record (defaults match the local stack):
```bash
python scripts/python/avro_producer.py
```
- Override defaults if needed:
```bash
BOOTSTRAP_SERVERS="localhost:19092,localhost:29092,localhost:39092" \
SCHEMA_REGISTRY_URL="http://localhost:8081" \
TOPIC="smoke_avro" \
MESSAGE_ID="42" \
python scripts/python/avro_producer.py
```

## Ground rules
- Prefer mounted configs over baked images.
- Keep stateful services on named volumes once they are added.
- Make startup/verifications explicit with healthchecks and CLI smoke tests as components arrive.
