# Kafka → ClickHouse (Local Pipeline Scaffold)

This repository starts as a minimal scaffold for an incremental Docker Compose–based data pipeline. Services are added one commit at a time; Kafka, Schema Registry, and ClickHouse are now running. See `SECURITY.md` for the current local-only security posture.

## Current state
- Kafka runs in KRaft mode (no ZooKeeper) with healthchecks, CLI smoke tests, and named volumes for persistence.
- Schema Registry and Kafka Connect are up with health checks; Connect uses the native ClickHouse sink plugin baked into the image.
- ClickHouse is a 2-node replicated cluster behind HAProxy, with Keeper coordination and persistent volumes per node.
- End-to-end Kafka → Connect → ClickHouse flow is validated via repeatable Avro smoke tests.
- Startup is health-ordered; bring the stack up with:
```bash
docker compose up -d
```

## Repository layout
- `docker-compose.yml` — Compose stack that grows one service at a time; currently includes Kafka (KRaft), Schema Registry, Kafka Connect, and ClickHouse.
- `configs/` — mounted configuration files for services (ClickHouse overrides in `configs/clickhouse`, connector config samples in `configs/connect`).
- `sql/` — ClickHouse schemas and setup scripts (DDLs live under `sql/ddl/`).
- `docker/` — custom images build contexts (e.g., Kafka Connect plugins).
- `scripts/` — helper scripts for local workflows.

## How to use this scaffold
1) Copy `.env.example` to `.env` and set required values (e.g., `CLUSTER_ID`).
2) Add one service or configuration change per commit to keep changes reviewable.
3) Document any new commands or smoke tests in `README.md` as the stack evolves.

## Environment file
- Docker Compose automatically loads `.env` at the repo root; use it to keep container names and host ports predictable across restarts.
- The repo commits `.env.example` only; `.env` itself is git-ignored for local overrides.
- Safe values: ports, volume paths, and other non-secret defaults.
- `CLUSTER_ID` is required for KRaft (the broker uses it to format storage on first start); generate one with:
```bash
docker run --rm confluentinc/cp-kafka:7.7.7 kafka-storage.sh random-uuid
```
- Keep secrets out of `.env` and this repo; inject them at runtime via your shell, a locally stored untracked file, or a secrets manager.

## Day-to-day ops
- Start stack (builds Kafka Connect image first):
```bash
scripts/docker_up.sh
```
- Start fresh (rebuild + recreate containers + fresh anonymous volumes):
```bash
scripts/docker_up.sh --recreate
```
- Stop stack:
```bash
scripts/docker_down.sh
```
- Stop and remove all volumes (named + anonymous):
```bash
scripts/docker_down.sh --remove_volumes
```
- Quick health:
```bash
docker compose ps
docker inspect "$(docker compose ps -q <svc>)" --format '{{json .State.Health}}'
```
- Logs (Kafka at WARN; Kafka Connect at INFO; ClickHouse at warning):
```bash
docker compose logs -f kafka-broker-1
docker compose logs -f kafka-connect
docker compose logs -f schema-registry
docker compose logs -f clickhouse-1
docker compose logs -f clickhouse-2
```
- Setup Python virtualenv + deps (pyenv):
```bash
scripts/setup_python.sh
```

## Logs & debugging
- Kafka brokers/controllers (repeat per node):
```bash
docker compose logs -f kafka-broker-1
```
Root log level is `WARN` to keep noise low; switch to `INFO` temporarily by exporting `KAFKA_LOG4J_ROOT_LOGLEVEL=INFO` before starting the stack:
```bash
export KAFKA_LOG4J_ROOT_LOGLEVEL=INFO
docker compose up -d
```
- Kafka Connect (worker/connector output):
```bash
docker compose logs -f kafka-connect
```
- Schema Registry:
```bash
docker compose logs -f schema-registry
```
- ClickHouse (logs also live at `/var/log/clickhouse-server/` inside the container):
```bash
docker compose logs -f clickhouse-1
docker compose logs -f clickhouse-2
```
- Quick health checks:
```bash
docker compose ps
docker inspect "$(docker compose ps -q <service>)" --format '{{json .State.Health}}'
```

## Endpoints reference
- **Kafka brokers (host / client-facing, SASL_PLAINTEXT):** `localhost:19092`, `localhost:29092`, `localhost:39092`
- **Kafka brokers (in-cluster):** `kafka-broker-1:9093`, `kafka-broker-2:9093`, `kafka-broker-3:9093`
- **Schema Registry:** [http://localhost:8081](http://localhost:8081) (in-cluster: [http://schema-registry:8081](http://schema-registry:8081))
- **Kafka Connect REST:** [http://localhost:8083](http://localhost:8083) (in-cluster: [http://kafka-connect:8083](http://kafka-connect:8083))
- **ClickHouse via HAProxy (HTTP LB):** [http://localhost:18123](http://localhost:18123) (in-cluster: [http://clickhouse-haproxy:8123](http://clickhouse-haproxy:8123))
- **ClickHouse (node 1):** HTTP [http://localhost:8123](http://localhost:8123), native TCP `localhost:9000` (in-cluster: `clickhouse-1:9000`)
- **ClickHouse (node 2):** HTTP [http://localhost:8124](http://localhost:8124), native TCP `localhost:9001`
- **ClickHouse Keeper:** `localhost:9181`

## Stack at a glance
- Kafka (KRaft): 3 controllers + 3 brokers, host client ports use SASL_PLAINTEXT.
- Schema Registry: backed by Kafka, reachable at `http://localhost:8081`.
- Kafka Connect: custom image; plugins baked from `docker/kafka-connect/plugins/`.
- ClickHouse HAProxy: HTTP load balancer across both ClickHouse nodes at `http://localhost:18123`.
- ClickHouse: 2-node cluster (ReplicatedMergeTree) backed by ClickHouse Keeper, each node on its own volume; node 1 exposed on 8123/9000 (`clickhouse-1`), node 2 on 8124/9001 (`clickhouse-2`).
- Log levels: Kafka controllers/brokers run at `WARN`, Kafka Connect at `INFO`, ClickHouse at `warning` with console output to reduce noise while keeping useful diagnostics.

## Kafka
### Cluster topology
```
                 Kafka KRaft Cluster
Controllers:  kafka-controller-1/2/3 (quorum on :9094)
   Brokers:   kafka-broker-1/2/3 (SASL on :9093 and host :19092/:29092/:39092)
 Schema Reg:  schema-registry (http://localhost:8081)
      Connect: kafka-connect (REST http://localhost:8083)
```

#### Broker vs controller split
- Controllers manage cluster metadata and leader elections (KRaft quorum).
- Brokers handle client traffic (produce/consume) and store topic data.
- This split mirrors production patterns while keeping the local stack small.

#### SASL/PLAIN placeholders (internal + host listeners enabled)
- Broker internal and host listeners use SASL_PLAINTEXT and read `/etc/kafka/secrets/broker_jaas.conf`.
- Client-side placeholders live in `configs/kafka/secrets/` (`client_jaas.conf`, `client.properties`) for later updates.
- Keep real credentials out of git; inject via `.env` or your shell when you decide to update clients.

### Kafka cluster (KRaft)
- Role:
  - three controller-only nodes + three broker-only nodes (no ZooKeeper),
  - image `confluentinc/cp-kafka:7.7.7`,
  - uses `CLUSTER_ID` to format storage if the log directory is empty,
  - config uses the `cp-kafka` Docker env var names (`KAFKA_PROCESS_ROLES`, `KAFKA_LISTENERS`, etc.).
- Endpoints:
  - brokers (host, SASL_PLAINTEXT): `localhost:19092`, `localhost:29092`, `localhost:39092`,
  - brokers (in-cluster): `kafka-broker-1:9093`, `kafka-broker-2:9093`, `kafka-broker-3:9093`,
  - controllers (in-cluster): `kafka-controller-1:9094`, `kafka-controller-2:9094`, `kafka-controller-3:9094`.
- Data:
  - brokers and controllers persist state in named Docker volumes (one per node),
  - reset state (removes volumes):
```bash
docker compose down -v
```
- Volumes visibility:
  - list this project’s named volumes:
```bash
docker volume ls --filter label=com.docker.compose.project=<project>
```
  - note: some images may create anonymous volumes via Dockerfile `VOLUME`; those won’t appear in `docker-compose.yml` unless we explicitly mount over them.
#### Run
```bash
docker compose up -d
```

#### Health
- Check container health (look for `healthy` in the `STATE` column):
```bash
docker compose ps
```
- Inspect probe output for a broker:
```bash
docker inspect "$(docker compose ps -q kafka-broker-1)" --format '{{json .State.Health}}'
```
- SASL check (broker startup):
```bash
docker compose logs -f kafka-broker-1
```
Confirm the broker reaches `Kafka Server started`.
- Inter-broker SASL check:
```bash
docker compose logs -f kafka-broker-2
```
Confirm there are no `Invalid username or password` errors.
- Logs (WARN by default; repeat per node). To increase detail temporarily:
```bash
export KAFKA_LOG4J_ROOT_LOGLEVEL=INFO
docker compose up -d
```

#### Smoke tests
- Prepare Kafka client properties inside the broker container (uses `.env` defaults if present):
```bash
set -a
source .env
set +a
docker compose exec -T \
  -e KAFKA_CLIENT_SASL_USERNAME="${KAFKA_CLIENT_SASL_USERNAME}" \
  -e KAFKA_CLIENT_SASL_PASSWORD="${KAFKA_CLIENT_SASL_PASSWORD}" \
  kafka-broker-1 bash -ec 'cat > /tmp/client.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_CLIENT_SASL_USERNAME}" password="${KAFKA_CLIENT_SASL_PASSWORD}";
EOF'
```
##### Topic lifecycle
- Create the topic (idempotent if it already exists):
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --create \
  --if-not-exists \
  --topic smoke-kafka \
  --replication-factor 3 \
  --partitions 1
```
- List topics (should include `smoke-kafka`):
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --list
```

##### Produce and consume
- Produce (sends lines as messages; end with Ctrl+D):
```bash
docker compose exec -T \
  kafka-broker-1 kafka-console-producer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --producer.config /tmp/client.properties \
  --topic smoke-kafka
```
- Consume from the start (reads historical messages; exits after 10):
```bash
docker compose exec -T \
  kafka-broker-1 kafka-console-consumer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --consumer.config /tmp/client.properties \
  --topic smoke-kafka \
  --from-beginning \
  --max-messages 10
```

##### Persistence check
- Restart the broker and list topics again (topic should still exist):
```bash
docker compose restart kafka-broker-1
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --list
```

### Schema Registry
- Role:
  - schema registry service backed by Kafka (stores schemas in an internal Kafka topic),
  - image `confluentinc/cp-schema-registry:7.7.7`,
  - exposed on `http://localhost:8081`.
- Health: Compose waits for `/subjects` to respond before starting Kafka Connect (healthcheck is built-in).
#### Run
- Start Schema Registry:
```bash
docker compose up -d schema-registry
```
- Logs:
```bash
docker compose logs -f schema-registry
```

#### Smoke tests
##### List subjects
- List registered subjects (empty `[]` if none yet). This also confirms Schema Registry can reach Kafka over SASL:
```bash
curl -s http://localhost:8081/subjects
```

##### Schema lifecycle (no producers/consumers yet)
- Set subject compatibility to BACKWARD (allows adding fields with defaults):
```bash
curl -s -X PUT -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"compatibility":"BACKWARD"}' \
  http://localhost:8081/config/smoke-avro-value
```
- Register v1 schema (creates the subject):
```bash
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"SmokeAvro\",\"namespace\":\"example\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"ts\",\"type\":\"string\"}]}"}' \
  http://localhost:8081/subjects/smoke-avro-value/versions
```
- List subject versions (should show `1`):
```bash
curl -s http://localhost:8081/subjects/smoke-avro-value/versions
```
- Print latest schema (full JSON, then the schema string):
```bash
curl -s http://localhost:8081/subjects/smoke-avro-value/versions/latest
curl -s http://localhost:8081/subjects/smoke-avro-value/versions/latest | jq -r .schema
```
- Check compatibility for a candidate schema (adds a field with default = backward compatible):
```bash
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"SmokeAvro\",\"namespace\":\"example\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"ts\",\"type\":\"string\"},{\"name\":\"source\",\"type\":\"string\",\"default\":\"unknown\"}]}"}' \
  http://localhost:8081/compatibility/subjects/smoke-avro-value/versions/latest
```
- Register v2 schema (extends the subject):
```bash
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"SmokeAvro\",\"namespace\":\"example\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"ts\",\"type\":\"string\"},{\"name\":\"source\",\"type\":\"string\",\"default\":\"unknown\"}]}"}' \
  http://localhost:8081/subjects/smoke-avro-value/versions
```

##### Avro messages (optional)
- Prepare Kafka client properties inside the Schema Registry container (uses `.env` defaults if present):
```bash
set -a
source .env
set +a
docker compose exec -T \
  -e KAFKA_CLIENT_SASL_USERNAME="${KAFKA_CLIENT_SASL_USERNAME}" \
  -e KAFKA_CLIENT_SASL_PASSWORD="${KAFKA_CLIENT_SASL_PASSWORD}" \
  schema-registry bash -ec 'cat > /tmp/client.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_CLIENT_SASL_USERNAME}" password="${KAFKA_CLIENT_SASL_PASSWORD}";
EOF'
```
- Create the topic for Avro messages:
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --create \
  --if-not-exists \
  --topic smoke-avro \
  --replication-factor 3 \
  --partitions 1
```
- Produce a few records (auto-registers schema under `<topic>-value` and sends Avro):
```bash
for id in 1 2 3 4 5; do
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf '{"id":"%s","ts":"%s"}\n' "${id}" "${ts}"
  sleep 1
done | docker compose exec -T \
  schema-registry kafka-avro-console-producer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --topic smoke-avro \
  --property schema.registry.url=http://schema-registry:8081 \
  --property value.schema='{"type":"record","name":"SmokeAvro","namespace":"example","fields":[{"name":"id","type":"string"},{"name":"ts","type":"string"}]}' \
  --producer.config /tmp/client.properties \
  --producer-property enable.metrics.push=false
```
- Consume (prints decoded Avro records; remove `--from-beginning` to read only new data):
```bash
docker compose exec -T \
  schema-registry kafka-avro-console-consumer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --topic smoke-avro \
  --from-beginning \
  --property schema.registry.url=http://schema-registry:8081 \
  --consumer.config /tmp/client.properties \
  --max-messages 5
```

- Verify Schema Registry registered the subject:
```bash
curl -s http://localhost:8081/subjects | jq -r '.[]' | rg '^smoke-avro-value$'
```

## Kafka Connect
- Role:
  - distributed Kafka Connect worker (no connectors installed yet),
  - image `kafka-clickhouse-kafka-connect:7.7.7` (built from `confluentinc/cp-kafka-connect:7.7.7`; plugins are baked in from local `docker/kafka-connect/plugins/` when present), sample ClickHouse sink config provided.
  - internal topics replicated across brokers for configs/offsets/status.
- Internal topics (restart-safe state stored in Kafka volumes):
  - `connect-configs`: connector/task configs, `partitions=1`, `replication-factor=3`, compacted.
  - `connect-offsets`: source offsets, `partitions=25`, `replication-factor=3`, compacted.
  - `connect-status`: connector/task status, `partitions=5`, `replication-factor=3`, compacted.
  - Connect auto-creates these when topic auto-creation is enabled; if you disable auto-creation, create them once with the commands below and they will persist via broker volumes.
- Endpoints:
  - REST: `http://localhost:8083` (in-cluster: `http://kafka-connect:8083`)
### Run
- Start Kafka Connect:
```bash
docker compose up -d kafka-connect
```
- Logs (INFO):
```bash
docker compose logs -f kafka-connect
```
### Smoke tests
- Check connectors list (should be `[]` initially):
```bash
curl -s http://localhost:8083/connectors
```
- Verify Connect worker status:
```bash
curl -s http://localhost:8083/ | jq
```
- Prepare Kafka client properties inside the broker container (uses `.env` defaults if present):
```bash
set -a
source .env
set +a
docker compose exec -T \
  -e KAFKA_CLIENT_SASL_USERNAME="${KAFKA_CLIENT_SASL_USERNAME}" \
  -e KAFKA_CLIENT_SASL_PASSWORD="${KAFKA_CLIENT_SASL_PASSWORD}" \
  kafka-broker-1 bash -ec 'cat > /tmp/client.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_CLIENT_SASL_USERNAME}" password="${KAFKA_CLIENT_SASL_PASSWORD}";
EOF'
```
- List internal topics via SASL (expects `connect-configs`, `connect-offsets`, `connect-status` once auto-created):
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --list | rg '^connect-(configs|offsets|status)$'
```
- (Optional) Pre-create the internal topics if topic auto-creation is disabled (uses SASL client config):
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic connect-configs \
  --replication-factor 3 --partitions 1 \
  --config cleanup.policy=compact --config min.insync.replicas=2
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic connect-offsets \
  --replication-factor 3 --partitions 25 \
  --config cleanup.policy=compact --config min.insync.replicas=2
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic connect-status \
  --replication-factor 3 --partitions 5 \
  --config cleanup.policy=compact --config min.insync.replicas=2
```

### Plugins (deterministic, image-based)
- Approach: custom image (`docker/kafka-connect/Dockerfile`) built on top of `confluentinc/cp-kafka-connect:7.7.7`; plugins are baked in from local `docker/kafka-connect/plugins/` on build, keeping versions pinned in source control and avoiding drift from host-mounted folders.
- Native ClickHouse sink: place the ClickHouse sink connector jar(s) and ClickHouse JDBC driver under `docker/kafka-connect/plugins/clickhouse-sink/` before building (all plugins are provided locally; no downloads during build).
- Add other plugins: download and unpack the connector into `docker/kafka-connect/plugins/<connector-name>/`.
- Rebuild and restart Connect:
```bash
docker compose build kafka-connect
docker compose up -d kafka-connect
```
- Confirm plugin shows up:
```bash
curl -s http://localhost:8083/connector-plugins | jq -r '.[].class'
```
- No connectors are bundled by default; add them under `docker/kafka-connect/plugins/` before building.

### Example ClickHouse sink connector (single topic → single table, native plugin)
- Config file: `configs/connect/clickhouse-sink.json` (maps topic `kafka-events` to table `kafka_events` via `topic2TableMap` for the native ClickHouse sink; uses HTTP host/port/username/password fields expected by the connector. SASL auth is handled by the Kafka Connect worker config in `docker-compose.yml`, so the connector JSON does not need extra Kafka auth settings.)
- Note: the native ClickHouse sink defaults to using the Kafka topic name as the table name unless `topic2TableMap` is provided. We keep hyphens in Kafka topics but underscores in ClickHouse table names, so the explicit map is required.
- Prerequisites:
  - ClickHouse table exists: create via `sql/ddl/clickhouse_kafka_sink.sql`.
  - Add the native ClickHouse sink connector (zip or jar) and ClickHouse JDBC driver jar to `docker/kafka-connect/plugins/clickhouse-sink/` before building (all local, no downloads).
  - Rebuild Connect to bake them in:
```bash
docker compose build kafka-connect
docker compose up -d kafka-connect
```
  - Confirm the class is available:
```bash
curl -s http://localhost:8083/connector-plugins | jq -r '.[].class' | rg ClickHouseSinkConnector
```
- Deploy (edit credentials/topic/table in the JSON if you changed them):
```bash
curl -s -X PUT -H "Content-Type: application/json" \
  --data @configs/connect/clickhouse-sink.json \
  http://localhost:8083/connectors/clickhouse-sink/config | jq
```
- Check status:
```bash
curl -s http://localhost:8083/connectors/clickhouse-sink/status | jq
```

### Python Avro tools
#### Setup
- Create a pyenv virtualenv and install dependencies:
```bash
scripts/setup_python.sh
pyenv activate kafka-clickhouse
```
#### Helper runner
- Run Python tools with `.env` loaded and the `kafka-clickhouse` pyenv activated:
```bash
scripts/run_python_tool.sh avro_producer.py
```

#### Producer
- Script: `scripts/python/avro_producer.py` (run via `scripts/run_python_tool.sh` for pyenv + `.env` compatibility).
- Run (defaults match the local stack; includes current UTC timestamp):
```bash
export KAFKA_CLIENT_SASL_USERNAME="client"
export KAFKA_CLIENT_SASL_PASSWORD="change_me"
scripts/run_python_tool.sh avro_producer.py
```
- Override defaults if needed:
```bash
BOOTSTRAP_SERVERS="localhost:19092,localhost:29092,localhost:39092" \
SCHEMA_REGISTRY_URL="http://localhost:8081" \
TOPIC="smoke-avro" \
MESSAGE_ID="42" \
MESSAGE_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
KAFKA_CLIENT_SASL_USERNAME="client" \
KAFKA_CLIENT_SASL_PASSWORD="change_me" \
scripts/run_python_tool.sh avro_producer.py
```
To use the in-cluster listener instead (run inside the Compose network) set:
```bash
BOOTSTRAP_SERVERS="kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093" \
KAFKA_CLIENT_SASL_USERNAME="client" \
KAFKA_CLIENT_SASL_PASSWORD="change_me" \
```

#### Consumer
- Script: `scripts/python/avro_consumer.py` (run via `scripts/run_python_tool.sh` for pyenv + `.env` compatibility).
- Run (defaults match the local stack):
```bash
export KAFKA_CLIENT_SASL_USERNAME="client"
export KAFKA_CLIENT_SASL_PASSWORD="change_me"
scripts/run_python_tool.sh avro_consumer.py
```
- Override defaults if needed:
```bash
BOOTSTRAP_SERVERS="localhost:19092,localhost:29092,localhost:39092" \
SCHEMA_REGISTRY_URL="http://localhost:8081" \
TOPIC="smoke-avro" \
GROUP_ID="smoke-avro-consumer" \
MAX_MESSAGES="5" \
KAFKA_CLIENT_SASL_USERNAME="client" \
KAFKA_CLIENT_SASL_PASSWORD="change_me" \
scripts/run_python_tool.sh avro_consumer.py
```
To use the in-cluster listener instead (run inside the Compose network) set:
```bash
BOOTSTRAP_SERVERS="kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093" \
KAFKA_CLIENT_SASL_USERNAME="client" \
KAFKA_CLIENT_SASL_PASSWORD="change_me" \
```

#### ClickHouse query (HTTP via HAProxy)
- Script: `scripts/python/query_clickhouse.py`
- Run (defaults match the local stack):
```bash
python scripts/python/query_clickhouse.py
```
- Override defaults if needed:
```bash
CLICKHOUSE_HTTP="http://localhost:18123" \
CLICKHOUSE_USER="admin" \
CLICKHOUSE_PASSWORD="clickhouse" \
TABLE="kafka_events" \
LIMIT=10 \
python scripts/python/query_clickhouse.py
```

## ClickHouse
- Role:
  - two-node ClickHouse cluster (ReplicatedMergeTree) with ClickHouse Keeper; sink target for Kafka Connect,
  - image `clickhouse/clickhouse-server:25.11`,
  - each node persists data in its own named Docker volume (`clickhouse_data_1`, `clickhouse_data_2`), no external operational DB required.
  - optional HTTP load balancer (HAProxy) for BI/REST clients on `http://localhost:18123` (routes to both nodes, checks `/ping`).
  - Endpoints:
    - HAProxy HTTP LB: `http://localhost:18123` (in-cluster: `http://clickhouse-haproxy:8123`)
    - node 1 HTTP/TCP: `http://localhost:8123`, `localhost:9000`
    - node 2 HTTP/TCP: `http://localhost:8124`, `localhost:9001`
    - ClickHouse Keeper: `localhost:9181`
  - Tip: point BI/HTTP clients (e.g., Metabase) at the HAProxy endpoint; it health-checks `/ping` and round-robins the two nodes.
### Credentials
- HTTP/TCP: configured via `.env` (`CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`; defaults in `.env.example` are `admin` / `clickhouse`)
  - Update `.env`, then start ClickHouse (see Run). Changing credentials later requires recreating the container.
  - Stock `default` user is removed; `configs/clickhouse/users.d/default-user.xml` creates `admin` from env vars. Add your own users as overrides in `configs/clickhouse/users.d/` if needed.
### Config overrides
- Mounted as additional include paths (defaults remain intact):
  - `configs/clickhouse/config.d` → `/etc/clickhouse-server/config.d`
  - `configs/clickhouse/users.d`   → `/etc/clickhouse-server/users.d`
  - `configs/clickhouse/node1/config.d` → `/etc/clickhouse-server/config.d` for node 1
  - `configs/clickhouse/node2/config.d` → `/etc/clickhouse-server/config.d` for node 2
  - `configs/clickhouse/users.d`        → `/etc/clickhouse-server/users.d` (shared)
- ClickHouse config layout docs: https://clickhouse.com/docs/operations/configuration-files
- Active overrides (per node directories):
  - `listen.xml` binds HTTP/native to all interfaces for local access.
  - `keeper.xml` points both nodes at ClickHouse Keeper.
  - `cluster.xml` defines the `clickhouse_cluster` with two replicas.
  - `00-macros.xml` sets `shard`/`replica` macros per node.
- Default admin user for local dev lives in `configs/clickhouse/users.d/default-user.xml` (matches `.env.example` credentials).
- To activate or add overrides: place a `.xml` file in the node-specific folders above (or shared users.d), then restart:
```bash
docker compose restart clickhouse
```
### Run
- Start Keeper and both nodes:
```bash
docker compose up -d clickhouse-keeper
docker compose up -d clickhouse-1 clickhouse-2
```
- If Keeper was started after the nodes (or fails healthcheck), restart in order:
```bash
docker compose stop clickhouse-1 clickhouse-2 clickhouse-keeper
# optional reset if you can discard data:
docker volume rm kafka-clickhouse_clickhouse_keeper_data kafka-clickhouse_clickhouse_data_1 kafka-clickhouse_clickhouse_data_2
docker compose up -d clickhouse-keeper
docker compose up -d clickhouse-1 clickhouse-2
```
- If Keeper reports `Connection refused` from nodes, ensure it listens on 0.0.0.0:9181 (see `configs/clickhouse/keeper/keeper.xml`) and recreate it:
```bash
docker compose stop clickhouse-keeper
docker compose rm -sf clickhouse-keeper
# optional reset if you can discard data:
docker volume rm kafka-clickhouse_clickhouse_keeper_data
docker compose up -d clickhouse-keeper
```
- Logs (warning; server logs also live in `/var/log/clickhouse-server/` inside the container):
```bash
docker compose logs -f clickhouse-1
docker compose logs -f clickhouse-2
```
### Smoke tests
- Ping via HAProxy (returns `Ok.`):
  ```bash
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" http://localhost:18123/ping
  ```
- Ping a specific node if needed:
  ```bash
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" http://localhost:8123/ping
  ```
- Healthcheck note: the container reports healthy after this succeeds (it may take a few seconds on first start):
```bash
clickhouse-client --query "SELECT 1"
```
- Confirm effective user/profile (verifies overrides are applied):
  ```bash
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
    'http://localhost:18123/?query=SELECT+currentUser(),+currentProfiles()'
  ```
- Verify replication and persistence:
  ```bash
  # create a test table ON CLUSTER and write one row (ReplicatedMergeTree)
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
    -X POST -d '' 'http://localhost:18123/?query=CREATE+TABLE+IF+NOT+EXISTS+smoke_clickhouse+ON+CLUSTER+clickhouse_cluster(id+UInt32)+ENGINE=ReplicatedMergeTree('"'"/clickhouse/{shard}/smoke_clickhouse"'"','"'"{replica}"'"')+ORDER+BY+ts+DESC'
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
    -X POST -d '' 'http://localhost:18123/?query=INSERT+INTO+smoke_clickhouse+VALUES(1)'

  # read from node 2 to confirm replication
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
    'http://localhost:8124/?query=SELECT+*+FROM+smoke_clickhouse'
  ```
- Play UI (opens in browser; uses admin credentials in query params):
  [http://localhost:8123/play?user=admin&password=clickhouse](http://localhost:8123/play?user=admin&password=clickhouse) (update the URL if you change credentials)

### Example table for Kafka ingestion
- DDL: `sql/ddl/clickhouse_kafka_sink.sql` defines a replicated `kafka_events` table (ReplicatedMergeTree with macros) to receive rows from Kafka.
- When to create: after ClickHouse and ClickHouse Keeper are up and before wiring a Kafka Connect sink; run once per environment.
- How to create on all replicas (preferred): run ON CLUSTER once from any node:
```bash
curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
  -X POST --data-binary @sql/ddl/clickhouse_kafka_sink.sql \
  'http://localhost:18123/?query='
```
- If your Kafka messages use different columns/types, edit `sql/ddl/clickhouse_kafka_sink.sql` accordingly, then rerun the command above.

## End-to-end smoke test: Schema Registry → Kafka → ClickHouse (Avro)
- Prereqs: ClickHouse table exists (`sql/ddl/clickhouse_kafka_sink.sql`), ClickHouse sink connector is RUNNING, Schema Registry up. The bundled connector config already uses Avro converters.
- Ensure SASL client credentials are set in `.env` or your shell: `KAFKA_CLIENT_SASL_USERNAME`, `KAFKA_CLIENT_SASL_PASSWORD`.
- One-shot script (non-interactive) that runs these steps (sources `.env` and exports variables for child commands; fails fast if the connector is not RUNNING):
```bash
scripts/smoke_test.sh
```
- Topic name uses a hyphen (`kafka-events`) to avoid Kafka’s metrics collision warning for dots vs underscores.
- Prepare Kafka client properties inside containers for the manual Kafka CLI steps:
```bash
set -a
source .env
set +a
docker compose exec -T \
  -e KAFKA_CLIENT_SASL_USERNAME="${KAFKA_CLIENT_SASL_USERNAME}" \
  -e KAFKA_CLIENT_SASL_PASSWORD="${KAFKA_CLIENT_SASL_PASSWORD}" \
  kafka-broker-1 bash -ec 'cat > /tmp/client.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_CLIENT_SASL_USERNAME}" password="${KAFKA_CLIENT_SASL_PASSWORD}";
EOF'
docker compose exec -T \
  -e KAFKA_CLIENT_SASL_USERNAME="${KAFKA_CLIENT_SASL_USERNAME}" \
  -e KAFKA_CLIENT_SASL_PASSWORD="${KAFKA_CLIENT_SASL_PASSWORD}" \
  schema-registry bash -ec 'cat > /tmp/client.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_CLIENT_SASL_USERNAME}" password="${KAFKA_CLIENT_SASL_PASSWORD}";
EOF'
```
- Apply the connector config (idempotent):
```bash
curl -s -X PUT -H "Content-Type: application/json" \
  --data @configs/connect/clickhouse-sink.json \
  http://localhost:8083/connectors/clickhouse-sink/config | jq
```
- Confirm the connector is RUNNING:
```bash
curl -s http://localhost:8083/connectors/clickhouse-sink/status | jq
```
- Ensure the replicated table exists on the cluster:
```bash
curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
  -X POST --data-binary @sql/ddl/clickhouse_kafka_sink.sql \
  'http://localhost:18123/?query='
```
- Register the Avro schema for the topic:
```bash
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"KafkaEvent\",\"namespace\":\"example\",\"fields\":[{\"name\":\"id\",\"type\":\"long\"},{\"name\":\"source\",\"type\":\"string\"},{\"name\":\"ts\",\"type\":\"string\"},{\"name\":\"payload\",\"type\":\"string\"}]}"}' \
  http://localhost:8081/subjects/kafka-events-value/versions
```
- Ensure the Kafka topic exists:
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic kafka-events \
  --replication-factor 3 --partitions 1
```
- Produce Avro messages (schema is registered; value converter is Avro):
```bash
docker compose exec -T \
  schema-registry kafka-avro-console-producer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --topic kafka-events \
  --property schema.registry.url=http://schema-registry:8081 \
  --property value.schema='{"type":"record","name":"KafkaEvent","namespace":"example","fields":[{"name":"id","type":"long"},{"name":"source","type":"string"},{"name":"ts","type":"string"},{"name":"payload","type":"string"}]}' \
  --producer.config /tmp/client.properties \
  --producer-property enable.metrics.push=false
```
- Send a few records with current UTC timestamps:
```bash
payloads=(hello world foo bar baz)
for id in 1 2 3 4 5; do
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  payload="${payloads[$((id - 1))]}"
  printf '{"id":%s,"source":"smoke","ts":"%s","payload":"%s"}\n' "${id}" "${ts}" "${payload}"
  sleep 1
done
```
- Verify rows landed in ClickHouse:
```bash
curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
  'http://localhost:18123/?query=SELECT+count(),+min(id),+max(id)+FROM+kafka_events'
curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
  'http://localhost:18123/?query=SELECT+*+FROM+kafka_events+ORDER+BY+ts+DESC+LIMIT+5'
```
- If anything fails, check connector status/logs:
```bash
curl -s http://localhost:8083/connectors/clickhouse-sink/status | jq
docker compose logs -f kafka-connect
```
- Further reading on Kafka data formats: https://www.automq.com/blog/avro-vs-json-schema-vs-protobuf-kafka-data-formats

## Ground rules
- Prefer mounted configs over baked images.
- Keep stateful services on named volumes once they are added.
- Make startup/verifications explicit with healthchecks and CLI smoke tests as components arrive.

## Common failure modes (quick triage)
- Brokers/controllers unhealthy: ensure `CLUSTER_ID` is set in `.env`, volumes aren’t from an old incompatible run, and check:
```bash
docker compose logs kafka-controller-*
```
- Schema Registry unhealthy: brokers must be healthy/reachable; tail:
```bash
docker compose logs schema-registry
```
- Kafka Connect task FAILED:
  - `Connection to ClickHouse is not active`: check ClickHouse/HAProxy health, credentials/port in connector config, and that the target table exists.
  - `Missing required config`: fix connector JSON and re-`PUT`.
- ClickHouse Keeper errors / `Coordination::Exception`: restart keeper first, then clickhouse-1/2; ensure keeper listens on `0.0.0.0:9181`; drop keeper/CH volumes only if you can discard state.
- Avro serialization errors: schema mismatch; verify the registered schema and the payload shape in producers.
- No rows in ClickHouse: confirm connector status (`/connectors/<name>/status`), topic has data, table exists ON CLUSTER, and queries use the right endpoint (`http://localhost:18123`).
