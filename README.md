# Kafka → ClickHouse (Local Pipeline Scaffold)

This repository starts as a minimal scaffold for an incremental Docker Compose–based data pipeline. Services are added one commit at a time; Kafka, Schema Registry, and ClickHouse are now running. See `SECURITY.md` for the current local-only security posture.

## Current state
- Kafka runs in KRaft mode (no ZooKeeper) with healthchecks, CLI smoke tests, and named volumes for persistence.
- Schema Registry is up with health checks; JSON schemas for `kafka-json-events` live there.
- ClickHouse is a 2-node replicated cluster behind HAProxy, with Keeper coordination and persistent volumes per node.
- End-to-end Kafka → ClickHouse (JSON) flow is validated via repeatable smoke tests.
- Startup is health-ordered; bring the stack up with:
```bash
scripts/docker_up.sh
```

## Repository layout
- `docker-compose.yml` — Compose stack that grows one service at a time; currently includes Kafka (KRaft), Schema Registry, and ClickHouse.
- `configs/` — mounted configuration files for services (ClickHouse overrides in `configs/clickhouse`).
- `sql/` — ClickHouse schemas and setup scripts (DDLs live under `sql/ddl/`).
- `scripts/` — helper scripts for local workflows.
- `docs/clickhouse/` — short ClickHouse developer notes and references.

## How to use this scaffold
1) Copy `.env.example` to `.env` and set required values (e.g., `CLUSTER_ID`).
2) Copy secrets templates into an ignored `secrets/` folder and fill in local passwords.
3) Add one service or configuration change per commit to keep changes reviewable.
4) Document any new commands or smoke tests in `README.md` as the stack evolves.

## Environment file
- Docker Compose automatically loads `.env` at the repo root; use it for non-secret defaults (names, ports, topics, table names).
- The repo commits `.env.example` only; `.env` itself is git-ignored for local overrides.
- `.env.example` is grouped by purpose (cluster settings, auth, endpoints, event topics/tables, smoke tests); keep it in sync with your local changes.
- Env quick map:
  - Kafka events: `KAFKA_INTERNAL_DB`, `KAFKA_INTERNAL_DB_DDL`, `KAFKA_JSON_EVENTS_TOPIC`, `KAFKA_JSON_EVENTS_SUBJECT`, `KAFKA_JSON_EVENTS_SCHEMA_FILE`, `KAFKA_JSON_EVENTS_TABLE`, `KAFKA_JSON_EVENTS_TABLE_DDL`, `KAFKA_JSON_EVENTS_STORE_TABLE`, `KAFKA_JSON_EVENTS_STORE_TABLE_DDL`, `KAFKA_JSON_EVENTS_STORE_MV_DDL`.
  - Smoke tests: `KAFKA_SMOKE_TEST_TOPIC`, `GROUP_ID`, `MAX_MESSAGES`, `MESSAGE_ID`, `LIMIT`.
  - Endpoints: `SCHEMA_REGISTRY_URL`, `SCHEMA_REGISTRY_URL_INTERNAL`, `CLICKHOUSE_HTTP`, `CLICKHOUSE_NODE1_HTTP`, `CLICKHOUSE_NODE2_HTTP`, `BOOTSTRAP_SERVERS`, `BOOTSTRAP_SERVERS_INTERNAL`.
- Before running any snippet that references `${...}`, run `source scripts/source_env.sh` in that shell.
- `CLUSTER_ID` is required for KRaft (the broker uses it to format storage on first start); generate one with:
```bash
docker run --rm confluentinc/cp-kafka:7.7.7 kafka-storage.sh random-uuid
```
- Keep secrets out of `.env` and this repo; store them in `secrets/local.env` or inject via your shell/secret manager.

## Secrets (local only)
- Templates live under `templates/secrets/`. Run the setup script to create local copies:
```bash
scripts/setup/initial_setup.sh
```
- `secrets/local.env` holds passwords for ClickHouse and Kafka SASL.
- `secrets/kafka/` holds the JAAS files and `client.properties` mounted into Kafka and Schema Registry. Replace the placeholders in `secrets/kafka/client.properties` after running setup.
- `secrets/clickhouse/` is mounted into ClickHouse for optional TLS/cert files.
- Portability note: `secrets/local.env` uses flat `KEY=VALUE` pairs so it can be reused as a CI env file or mapped directly into Kubernetes `envFrom`/Secret keys later.
## Local environment
- Load `.env` + `secrets/local.env` into your current shell:
```bash
source scripts/source_env.sh
```

## Day-to-day ops
- Start stack:
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
- Logs (Kafka at WARN; Schema Registry at INFO; ClickHouse at warning):
```bash
docker compose logs -f kafka-broker-1
docker compose logs -f schema-registry
docker compose logs -f clickhouse-1
docker compose logs -f clickhouse-2
```
- Setup Python virtualenv + deps (pyenv):
```bash
scripts/setup/setup_python.sh
```

## Logs & debugging
- Kafka brokers/controllers (repeat per node):
```bash
docker compose logs -f kafka-broker-1
```
Root log level is `WARN` to keep noise low; switch to `INFO` temporarily by setting `KAFKA_LOG4J_ROOT_LOGLEVEL=INFO` in `.env` before starting the stack:
```bash
docker compose up -d
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
- **ClickHouse via HAProxy (HTTP LB):** [http://localhost:18123](http://localhost:18123) (in-cluster: [http://clickhouse-haproxy:8123](http://clickhouse-haproxy:8123))
- **ClickHouse (node 1):** HTTP [http://localhost:8123](http://localhost:8123), native TCP `localhost:9000` (in-cluster: `clickhouse-1:9000`)
- **ClickHouse (node 2):** HTTP [http://localhost:8124](http://localhost:8124), native TCP `localhost:9001`
- **ClickHouse Keeper:** `localhost:9181`

## Stack at a glance
- Kafka (KRaft): 3 controllers + 3 brokers, host client ports use SASL_PLAINTEXT.
- Schema Registry: backed by Kafka, reachable at `http://localhost:8081`.
- ClickHouse HAProxy: HTTP load balancer across both ClickHouse nodes at `http://localhost:18123`.
- ClickHouse: 2-node cluster (ReplicatedMergeTree) backed by ClickHouse Keeper, each node on its own volume; node 1 exposed on 8123/9000 (`clickhouse-1`), node 2 on 8124/9001 (`clickhouse-2`).
- Log levels: Kafka controllers/brokers run at `WARN`, Schema Registry at `INFO`, ClickHouse at `warning` with console output to reduce noise while keeping useful diagnostics.

## Kafka
### Cluster topology
```
              Kafka KRaft Cluster
Controllers:  kafka-controller-1/2/3 (quorum on :9094)
   Brokers:   kafka-broker-1/2/3 (SASL on :9093 and host :19092/:29092/:39092)
 Schema Reg:  schema-registry (http://localhost:8081)
```

#### Broker vs controller split
- Controllers manage cluster metadata and leader elections (KRaft quorum).
- Brokers handle client traffic (produce/consume) and store topic data.
- This split mirrors production patterns while keeping the local stack small.

#### SASL/PLAIN placeholders (internal + host listeners enabled)
- Broker internal and host listeners use SASL_PLAINTEXT and read `/etc/kafka/secrets/broker_jaas.conf`.
- Client-side placeholders live in `templates/secrets/kafka/` (`client_jaas.conf`, `client.properties`) for local copies.
- Keep real credentials out of git; use `secrets/local.env` or your shell when you decide to update clients.

### Kafka cluster (KRaft)
- Role:
  - three controller-only nodes + three broker-only nodes (no ZooKeeper),
  - image `confluentinc/cp-kafka:7.7.7`,
  - uses `CLUSTER_ID` to format storage if the log directory is empty,
  - config follows the `cp-kafka` Docker env var naming conventions (see Confluent docs).
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
- Logs (WARN by default; repeat per node). To increase detail temporarily, set `KAFKA_LOG4J_ROOT_LOGLEVEL=INFO` in `.env`, then restart:
```bash
docker compose up -d
```

#### Smoke tests
- Ensure `secrets/kafka/client.properties` contains real credentials (not `${...}` placeholders) and is mounted at `/etc/kafka/secrets/client.properties` in the broker container.
##### Topic lifecycle
- Create the topic (idempotent if it already exists). Set `KAFKA_SMOKE_TEST_TOPIC` and `BOOTSTRAP_SERVERS_INTERNAL` in `.env` first:
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config /etc/kafka/secrets/client.properties \
  --create \
  --if-not-exists \
  --topic "${KAFKA_SMOKE_TEST_TOPIC}" \
  --replication-factor 3 \
  --partitions 1
```
- List topics (should include `${KAFKA_SMOKE_TEST_TOPIC}`):
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config /etc/kafka/secrets/client.properties \
  --list
```

##### Produce and consume
- Produce (sends lines as messages; end with Ctrl+D):
```bash
docker compose exec -T \
  kafka-broker-1 kafka-console-producer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --producer.config /etc/kafka/secrets/client.properties \
  --topic "${KAFKA_SMOKE_TEST_TOPIC}"
```
- Consume from the start (reads historical messages; exits after 10):
```bash
docker compose exec -T \
  kafka-broker-1 kafka-console-consumer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --consumer.config /etc/kafka/secrets/client.properties \
  --topic "${KAFKA_SMOKE_TEST_TOPIC}" \
  --from-beginning \
  --max-messages 10
```

##### Persistence check
- Restart the broker and list topics again (topic should still exist):
```bash
docker compose restart kafka-broker-1
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config /etc/kafka/secrets/client.properties \
  --list
```

## Schema Registry (JSON Schema)
- Role:
  - stores JSON Schema definitions for Kafka topics (data contracts),
  - image `confluentinc/cp-schema-registry:7.7.7`,
  - exposed on `http://localhost:8081`.
- Endpoints:
  - `SCHEMA_REGISTRY_URL` for host access,
  - `SCHEMA_REGISTRY_URL_INTERNAL` for in-cluster access.
### Run
- Start Schema Registry:
```bash
docker compose up -d schema-registry
```
- Logs:
```bash
docker compose logs -f schema-registry
```
### JSON schema for `kafka-json-events`
- Register the JSON schema (creates/updates the subject):
```bash
jq -n --slurpfile schema "${KAFKA_JSON_EVENTS_SCHEMA_FILE}" \
  '{schemaType:"JSON", schema: ($schema[0] | tojson)}' | \
  curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
    --data @- \
    "${SCHEMA_REGISTRY_URL}/subjects/${KAFKA_JSON_EVENTS_SUBJECT}/versions"
```
- List subjects (should include `${KAFKA_JSON_EVENTS_SUBJECT}`):
```bash
curl -s "${SCHEMA_REGISTRY_URL}/subjects"
```

### Python Kafka tools
#### Setup
- Create a pyenv virtualenv and install dependencies:
```bash
scripts/setup/setup_python.sh
pyenv activate kafka-clickhouse
```
#### Environment
- Before running Python tools, load `.env` + `secrets/local.env` into your shell:
```bash
source scripts/source_env.sh
```
#### Helper runner
- Run Python tools with `.env` + `secrets/local.env` loaded and the `kafka-clickhouse` pyenv activated:
```bash
scripts/run_python_tool.sh kafka_json_producer.py
```

#### JSON producer
- Script: `scripts/python/kafka_json_producer.py` (run via `scripts/run_python_tool.sh` for pyenv + `.env` compatibility).
- Run (uses values from `.env` + `secrets/local.env`, writes JSON to `kafka-json-events`):
```bash
scripts/run_python_tool.sh kafka_json_producer.py
```
- To change inputs, update `BOOTSTRAP_SERVERS`, `KAFKA_JSON_EVENTS_TOPIC`, and `MESSAGE_ID` in `.env` and re-run.

#### JSON consumer
- Script: `scripts/python/kafka_json_consumer.py` (run via `scripts/run_python_tool.sh` for pyenv + `.env` compatibility).
- Run (uses values from `.env` + `secrets/local.env`):
```bash
scripts/run_python_tool.sh kafka_json_consumer.py
```
- To change inputs, update `BOOTSTRAP_SERVERS`, `KAFKA_JSON_EVENTS_TOPIC`, `GROUP_ID`, and `MAX_MESSAGES` in `.env` and re-run.

#### ClickHouse query (HTTP via HAProxy)
- Script: `scripts/python/query_clickhouse.py`
- Run (uses values from `.env` + `secrets/local.env`):
```bash
scripts/run_python_tool.sh query_clickhouse.py
```
- To change the endpoint or query scope, update `CLICKHOUSE_HTTP`, `KAFKA_JSON_EVENTS_STORE_TABLE`, `LIMIT`, and the reader credentials in `secrets/local.env` and re-run.

## ClickHouse
- Role:
  - two-node ClickHouse cluster (ReplicatedMergeTree) with ClickHouse Keeper; sink target for Kafka JSON ingestion,
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
- HTTP/TCP: configured via `.env` (usernames) + `secrets/local.env` (passwords)
  - Update `secrets/local.env`, then start ClickHouse (see Run). Changing credentials later requires recreating the container.
  - Default user is removed to enforce auth.
  - `configs/clickhouse/users.d/50-users-auth.xml` creates `admin` and `reader` users using env-sourced passwords; the `50-` prefix ensures it loads after ClickHouse's generated `default-user.xml`.
  - Reader restrictions are enforced via profiles (`readonly=2` to allow safe settings changes; `allow_ddl=0` to block DDL).
- `CLICKHOUSE_ADMIN_USER` is expected to remain `admin` unless you also update the ClickHouse user config.
  - To change admin credentials: update `CLICKHOUSE_ADMIN_PASSWORD` in `secrets/local.env`, then recreate ClickHouse:
```bash
docker compose down
docker compose up -d clickhouse-keeper clickhouse-1 clickhouse-2
```
  - Verify auth is enforced (default removed) and admin access works:
```bash
# should fail without credentials
curl -sS "${CLICKHOUSE_HTTP}/?query=SELECT+1"
# should succeed with admin credentials
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+currentUser()"
```
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
  - `cors.xml` enables `add_http_cors_header` for HTTP UI queries.
- Default admin user for local dev lives in `configs/clickhouse/users.d/50-users-auth.xml` (matches `templates/secrets/local.env`).
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
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" "${CLICKHOUSE_HTTP}/ping"
  ```
- Ping a specific node if needed:
  ```bash
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" "${CLICKHOUSE_NODE1_HTTP}/ping"
  ```
- Healthcheck note: the container reports healthy after this succeeds (it may take a few seconds on first start):
```bash
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_HTTP}/?query=SELECT+1"\
```
- Confirm effective user/profile (verifies overrides are applied):
  ```bash
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_HTTP}/?query=SELECT+currentUser(),+currentProfiles()"
  ```
- Verify replication and persistence:
  ```bash
  # create a test table ON CLUSTER and write one row (ReplicatedMergeTree)
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    -X POST -d '' "${CLICKHOUSE_HTTP}/?query=CREATE+TABLE+IF+NOT+EXISTS+smoke_test_replication+ON+CLUSTER+clickhouse_cluster(id+UInt32)+ENGINE=ReplicatedMergeTree(%27/clickhouse/{shard}/smoke_test_replication%27,%27{replica}%27)+ORDER+BY+id"
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    -X POST -d '' "${CLICKHOUSE_HTTP}/?query=INSERT+INTO+smoke_test_replication+VALUES(1)"

  # read from node 2 to confirm replication
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_NODE2_HTTP}/?query=SELECT+*+FROM+smoke_test_replication"
  ```
- Kafka JSON store read (stable; queries persisted rows):
  ```bash
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_HTTP}/?query=SELECT+*+FROM+${KAFKA_JSON_EVENTS_STORE_TABLE}+ORDER+BY+ts+DESC+LIMIT+5"
  ```
- Play UI (opens in browser; enter admin credentials from `secrets/local.env`):
  [http://localhost:8123/play](http://localhost:8123/play)

### Auth checks
- Permission profiles:
  - reader: `readonly=2`, `allow_ddl=0`, `allow_introspection_functions=0` (read-only, with settings-level readonly mode so UI per-query settings are allowed)
- Verify effective grants (use the passwords from `secrets/local.env`):
```bash
curl -sS -u "${CLICKHOUSE_READER_USER}:${CLICKHOUSE_READER_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SHOW+GRANTS"
```

### Example table for Kafka ingestion
- DDLs:
  - `sql/ddl/clickhouse_kafka_json_events.sql` defines the ingest-only `kafka_internal.kafka_json_events` Kafka engine table (JSON).
  - `sql/ddl/clickhouse_kafka_json_events_store_table.sql` defines a persisted `kafka_json_events_store` table and `sql/ddl/clickhouse_kafka_json_events_store_mv.sql` defines a materialized view that copies from the Kafka engine table for stable UI queries.
- `kafka_internal.kafka_json_events` reads from the `kafka-json-events` topic using `JSONEachRow`; update the Kafka settings (topic, SASL credentials, format) if your environment differs.
- The Kafka engine table is a stream reader (not durable storage). Use `kafka_json_events_store` for stable querying.
- When to create: after ClickHouse and ClickHouse Keeper are up and before producing JSON messages; run once per environment.
- How to create on all replicas (preferred): run ON CLUSTER once from any node:
```bash
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  -X POST --data-binary @sql/ddl/clickhouse_kafka_internal_db.sql \
  "${CLICKHOUSE_HTTP}/?query="
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  -X POST --data-binary @sql/ddl/clickhouse_kafka_json_events.sql \
  "${CLICKHOUSE_HTTP}/?query="
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  -X POST --data-binary @sql/ddl/clickhouse_kafka_json_events_store_table.sql \
  "${CLICKHOUSE_HTTP}/?query="
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  -X POST --data-binary @sql/ddl/clickhouse_kafka_json_events_store_mv.sql \
  "${CLICKHOUSE_HTTP}/?query="
```
- If your Kafka messages use different columns/types, update the relevant DDLs (JSON engine, store table, MV), then rerun the commands above.

## End-to-end smoke test: Schema Registry → Kafka → ClickHouse (JSON)
- Prereqs: ClickHouse tables exist (`sql/ddl/clickhouse_kafka_internal_db.sql`, `sql/ddl/clickhouse_kafka_json_events.sql`, `sql/ddl/clickhouse_kafka_json_events_store_table.sql`, `sql/ddl/clickhouse_kafka_json_events_store_mv.sql`) and Kafka + Schema Registry + ClickHouse are up.
- Ensure `.env` + `secrets/local.env` include the Kafka client credentials.
- Load `.env` + `secrets/local.env` into your shell before running any commands in this section:
```bash
source scripts/source_env.sh
```
- One-shot script (non-interactive) that runs the JSON pipeline steps (including JSON schema registration):
```bash
scripts/tests/smoke_test.sh
```
- Manual steps (quick check):
  - Ensure `secrets/kafka/client.properties` contains real credentials and is mounted at `/etc/kafka/secrets/client.properties`.
  - Register/update the JSON schema:
```bash
jq -n --slurpfile schema "${KAFKA_JSON_EVENTS_SCHEMA_FILE}" \
  '{schemaType:"JSON", schema: ($schema[0] | tojson)}' | \
  curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
    --data @- \
    "${SCHEMA_REGISTRY_URL}/subjects/${KAFKA_JSON_EVENTS_SUBJECT}/versions"
```
  - Create the JSON topic:
```bash
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config /etc/kafka/secrets/client.properties \
  --create --if-not-exists --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --replication-factor 3 --partitions 1
```
  - Produce one JSON message:
```bash
ts="$(date -u +"%Y-%m-%d %H:%M:%S")"
printf '{"id":101,"source":"smoke-json","ts":"%s","payload":"hello-json"}\n' "${ts}" | \
  docker compose exec -T \
  kafka-broker-1 kafka-console-producer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --producer.config /etc/kafka/secrets/client.properties
```
  - Verify the JSON store table via HAProxy:
```bash
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+*+FROM+${KAFKA_JSON_EVENTS_STORE_TABLE}+ORDER+BY+ts+DESC+LIMIT+1"
```

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
- ClickHouse Keeper errors / `Coordination::Exception`: restart keeper first, then clickhouse-1/2; ensure keeper listens on `0.0.0.0:9181`; drop keeper/CH volumes only if you can discard state.
- ClickHouse `CANNOT_CREATE_TIMER` / `Failed to create thread timer`: local Docker can exhaust timer resources; this repo disables the query profiler via `configs/clickhouse/users.d/disable-query-profiler.xml` and the global profiler via `configs/clickhouse/node1/config.d/disable-global-profiler.xml` plus `configs/clickhouse/node2/config.d/disable-global-profiler.xml`. How to verify: `docker compose restart clickhouse-1 clickhouse-2`, then confirm the logs no longer show `CANNOT_CREATE_TIMER`.
- No rows in ClickHouse: confirm the Kafka topic has data, the Kafka engine table settings match your broker/topic/format, and queries use the right endpoint (`${CLICKHOUSE_HTTP}`); check ClickHouse logs if ingestion stalls.
