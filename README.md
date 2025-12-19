# Kafka → ClickHouse (Local Pipeline Scaffold)

This repository starts as a minimal scaffold for an incremental Docker Compose–based data pipeline. Services are added one commit at a time; Kafka, Schema Registry, and ClickHouse are now running.

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
- `CLUSTER_ID` is required for KRaft (the broker uses it to format storage on first start); generate one with `docker run --rm confluentinc/cp-kafka:7.7.7 kafka-storage.sh random-uuid`.
- Keep secrets out of `.env` and this repo; inject them at runtime via your shell, a locally stored untracked file, or a secrets manager.

## Helper scripts
- Start the stack (builds the custom Kafka Connect image first): `scripts/docker_up.sh`
- Start with image rebuild + container recreation + fresh anonymous volumes: `scripts/docker_up.sh --recreate`
- Stop the stack: `scripts/docker_down.sh`
- Stop and remove volumes (including anonymous ones): `scripts/docker_down.sh --remove_volumes`
- Setup Python virtualenv + deps (pyenv required): `scripts/setup_python.sh`

## Endpoints reference
- **Kafka brokers (host / client-facing):** `localhost:19092`, `localhost:29092`, `localhost:39092`
- **Kafka brokers (in-cluster):** `kafka-broker-1:9093`, `kafka-broker-2:9093`, `kafka-broker-3:9093`
- **Schema Registry:** [http://localhost:8081](http://localhost:8081) (in-cluster: [http://schema-registry:8081](http://schema-registry:8081))
- **Kafka Connect REST:** [http://localhost:8083](http://localhost:8083) (in-cluster: [http://kafka-connect:8083](http://kafka-connect:8083))
- **ClickHouse via HAProxy (HTTP LB):** [http://localhost:18123](http://localhost:18123) (in-cluster: [http://clickhouse-haproxy:8123](http://clickhouse-haproxy:8123))
- **ClickHouse (node 1):** HTTP [http://localhost:8123](http://localhost:8123), native TCP `localhost:9000` (in-cluster: `clickhouse-1:9000`)
- **ClickHouse (node 2):** HTTP [http://localhost:8124](http://localhost:8124), native TCP `localhost:9001`
- **ClickHouse Keeper:** `localhost:9181`

## Stack at a glance
- Kafka (KRaft): 3 controllers + 3 brokers, client ports exposed on localhost.
- Schema Registry: backed by Kafka, reachable at `http://localhost:8081`.
- Kafka Connect: custom image; plugins baked from `docker/kafka-connect/plugins/`.
- ClickHouse HAProxy: HTTP load balancer across both ClickHouse nodes at `http://localhost:18123`.
- ClickHouse: 2-node cluster (ReplicatedMergeTree) backed by ClickHouse Keeper, each node on its own volume; node 1 exposed on 8123/9000 (`clickhouse-1`), node 2 on 8124/9001 (`clickhouse-2`).

## Kafka
### Cluster topology
```
                 Kafka KRaft Cluster
Controllers:  kafka-controller-1/2/3 (quorum on :9094)
   Brokers:   kafka-broker-1/2/3 (clients on :9093, host :19092/:29092/:39092)
 Schema Reg:  schema-registry (http://localhost:8081)
      Connect: kafka-connect (REST http://localhost:8083)
```

#### Broker vs controller split
- Controllers manage cluster metadata and leader elections (KRaft quorum).
- Brokers handle client traffic (produce/consume) and store topic data.
- This split mirrors production patterns while keeping the local stack small.

### Kafka cluster (KRaft)
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
#### Run
- `docker compose up -d`

#### Health
- `docker compose ps` (look for `healthy` in the `STATE` column)
- `docker inspect "$(docker compose ps -q kafka-broker-1)" --format '{{json .State.Health}}'` (probe status and last output)

#### Smoke tests
##### Topic lifecycle
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

##### Produce and consume
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

##### Persistence check
- Restart the broker and list topics again (topic should still exist):
```bash
docker compose restart kafka-broker-1
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --list
```

### Schema Registry
- Role:
  - schema registry service backed by Kafka (stores schemas in an internal Kafka topic),
  - image `confluentinc/cp-schema-registry:7.7.7`,
  - exposed on `http://localhost:8081`.
#### Run
- `docker compose up -d schema-registry`

#### Smoke tests
##### List subjects
- List registered subjects (empty `[]` if none yet):
  `curl -s http://localhost:8081/subjects`

##### Schema lifecycle (no producers/consumers yet)
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

##### Avro messages (optional)
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
  --property value.schema='{"type":"record","name":"SmokeAvro","namespace":"example","fields":[{"name":"id","type":"string"}]}' \
  --producer-property enable.metrics.push=false
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
- `docker compose up -d kafka-connect`
### Smoke tests
- Check connectors list (should be `[]` initially):
  `curl -s http://localhost:8083/connectors`
- Verify Connect worker status:
  `curl -s http://localhost:8083/ | jq`
- (Optional) Pre-create the internal topics if topic auto-creation is disabled:
```bash
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --create --if-not-exists --topic connect-configs \
  --replication-factor 3 --partitions 1 \
  --config cleanup.policy=compact --config min.insync.replicas=2
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --create --if-not-exists --topic connect-offsets \
  --replication-factor 3 --partitions 25 \
  --config cleanup.policy=compact --config min.insync.replicas=2
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
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
- Config file: `configs/connect/clickhouse-sink.json` (maps topic `kafka_events` to table `kafka_events` using the native ClickHouse sink; uses HTTP host/port/username/password fields expected by the connector).
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

#### Producer
- Script: `scripts/python/avro_producer.py`
- Run (defaults match the local stack):
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

#### Consumer
- Script: `scripts/python/avro_consumer.py`
- Run (defaults match the local stack):
```bash
python scripts/python/avro_consumer.py
```
- Override defaults if needed:
```bash
BOOTSTRAP_SERVERS="localhost:19092,localhost:29092,localhost:39092" \
SCHEMA_REGISTRY_URL="http://localhost:8081" \
TOPIC="smoke_avro" \
GROUP_ID="smoke_avro_consumer" \
MAX_MESSAGES="5" \
python scripts/python/avro_consumer.py
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
- To activate or add overrides: place a `.xml` file in the node-specific folders above (or shared users.d), then `docker compose restart clickhouse`.
### Run
- `docker compose up -d clickhouse-keeper && docker compose up -d clickhouse-1 clickhouse-2`
- If Keeper was started after the nodes (or fails healthcheck), restart in order:
  - `docker compose stop clickhouse-1 clickhouse-2 clickhouse-keeper`
  - optional reset if you can discard data: `docker volume rm kafka-clickhouse_clickhouse_keeper_data kafka-clickhouse_clickhouse_data_1 kafka-clickhouse_clickhouse_data_2`
  - `docker compose up -d clickhouse-keeper`
  - `docker compose up -d clickhouse-1 clickhouse-2`
- If Keeper reports `Connection refused` from nodes, ensure it listens on 0.0.0.0:9181 (see `configs/clickhouse/keeper/keeper.xml`) and recreate it:
  - `docker compose stop clickhouse-keeper`
  - `docker compose rm -sf clickhouse-keeper`
  - optional reset if you can discard data: `docker volume rm kafka-clickhouse_clickhouse_keeper_data`
  - `docker compose up -d clickhouse-keeper`
### Smoke tests
- Ping via HAProxy (returns `Ok.`):
  ```bash
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" http://localhost:18123/ping
  ```
- Ping a specific node if needed:
  ```bash
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" http://localhost:8123/ping
  ```
- Healthcheck note: the container reports healthy after `clickhouse-client --query "SELECT 1"` succeeds (it may take a few seconds on first start).
- Confirm effective user/profile (verifies overrides are applied):
  ```bash
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
    'http://localhost:18123/?query=SELECT+currentUser(),+currentProfiles()'
  ```
- Verify replication and persistence:
  ```bash
  # create a test table ON CLUSTER and write one row (ReplicatedMergeTree)
  curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
    -X POST -d '' 'http://localhost:18123/?query=CREATE+TABLE+IF+NOT+EXISTS+smoke_clickhouse+ON+CLUSTER+clickhouse_cluster(id+UInt32)+ENGINE=ReplicatedMergeTree('"'"/clickhouse/{shard}/smoke_clickhouse"'"','"'"{replica}"'"')+ORDER+BY+id'
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
- Apply the connector config (idempotent):
```bash
curl -s -X PUT -H "Content-Type: application/json" \
  --data @configs/connect/clickhouse-sink.json \
  http://localhost:8083/connectors/clickhouse-sink/config | jq
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
  http://localhost:8081/subjects/kafka_events-value/versions
```
- Ensure the Kafka topic exists:
```bash
docker compose exec kafka-broker-1 kafka-topics \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --create --if-not-exists --topic kafka_events \
  --replication-factor 3 --partitions 1
```
- Produce Avro messages (schema is registered; value converter is Avro):
```bash
docker compose exec -T schema-registry kafka-avro-console-producer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --topic kafka_events \
  --property schema.registry.url=http://schema-registry:8081 \
  --property value.schema='{"type":"record","name":"KafkaEvent","namespace":"example","fields":[{"name":"id","type":"long"},{"name":"source","type":"string"},{"name":"ts","type":"string"},{"name":"payload","type":"string"}]}' \
  --producer-property enable.metrics.push=false
```
- Type a few records (one per line), then end with Ctrl+D:
```json
{"id":1,"source":"smoke","ts":"2025-12-18T00:00:00Z","payload":"hello"}
{"id":2,"source":"smoke","ts":"2025-12-18T00:00:01Z","payload":"world"}
{"id":3,"source":"smoke","ts":"2025-12-18T00:00:02Z","payload":"foo"}
{"id":4,"source":"smoke","ts":"2025-12-18T00:00:03Z","payload":"bar"}
{"id":5,"source":"smoke","ts":"2025-12-18T00:00:04Z","payload":"baz"}
```
- Verify rows landed in ClickHouse:
```bash
curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
  'http://localhost:18123/?query=SELECT+count(),+min(id),+max(id)+FROM+kafka_events'
curl -sS -u "${CLICKHOUSE_USER:-admin}:${CLICKHOUSE_PASSWORD:-clickhouse}" \
  'http://localhost:18123/?query=SELECT+*+FROM+kafka_events+ORDER+BY+id'
```
- If anything fails, check connector status/logs:
  - `curl -s http://localhost:8083/connectors/clickhouse-sink/status | jq`
  - `docker compose logs -f kafka-connect`
- Further reading on Kafka data formats: https://www.automq.com/blog/avro-vs-json-schema-vs-protobuf-kafka-data-formats

## Ground rules
- Prefer mounted configs over baked images.
- Keep stateful services on named volumes once they are added.
- Make startup/verifications explicit with healthchecks and CLI smoke tests as components arrive.
