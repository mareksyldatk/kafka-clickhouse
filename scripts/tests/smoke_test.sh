#!/usr/bin/env bash
set -euo pipefail

# Non-interactive end-to-end smoke test:
# Schema Registry (JSON Schema) -> Kafka (JSON) -> ClickHouse (Kafka engine + MV) via HAProxy.
#
# Prereqs:
# - Stack is up and healthy (kafka, schema-registry, clickhouse-keeper, clickhouse-1/2, haproxy).
# - JSON DDLs exist for the Kafka engine table and the store table.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

: "${CLICKHOUSE_ADMIN_USER:?Missing CLICKHOUSE_ADMIN_USER (run: source scripts/source_env.sh)}"
: "${CLICKHOUSE_ADMIN_PASSWORD:?Missing CLICKHOUSE_ADMIN_PASSWORD (run: source scripts/source_env.sh)}"
: "${KAFKA_CLIENT_SASL_USERNAME:?Missing KAFKA_CLIENT_SASL_USERNAME (run: source scripts/source_env.sh)}"
: "${KAFKA_CLIENT_SASL_PASSWORD:?Missing KAFKA_CLIENT_SASL_PASSWORD (run: source scripts/source_env.sh)}"
: "${KAFKA_INTERNAL_DB:?Missing KAFKA_INTERNAL_DB (run: source scripts/source_env.sh)}"
: "${KAFKA_INTERNAL_DB_DDL:?Missing KAFKA_INTERNAL_DB_DDL (run: source scripts/source_env.sh)}"
: "${KAFKA_JSON_EVENTS_TABLE:?Missing KAFKA_JSON_EVENTS_TABLE (run: source scripts/source_env.sh)}"
: "${KAFKA_JSON_EVENTS_TABLE_DDL:?Missing KAFKA_JSON_EVENTS_TABLE_DDL (run: source scripts/source_env.sh)}"
: "${KAFKA_JSON_EVENTS_TOPIC:?Missing KAFKA_JSON_EVENTS_TOPIC (run: source scripts/source_env.sh)}"
: "${KAFKA_JSON_EVENTS_SUBJECT:?Missing KAFKA_JSON_EVENTS_SUBJECT (run: source scripts/source_env.sh)}"
: "${KAFKA_JSON_EVENTS_SCHEMA_FILE:?Missing KAFKA_JSON_EVENTS_SCHEMA_FILE (run: source scripts/source_env.sh)}"
: "${KAFKA_JSON_EVENTS_STORE_TABLE:?Missing KAFKA_JSON_EVENTS_STORE_TABLE (run: source scripts/source_env.sh)}"
: "${KAFKA_JSON_EVENTS_STORE_TABLE_DDL:?Missing KAFKA_JSON_EVENTS_STORE_TABLE_DDL (run: source scripts/source_env.sh)}"
: "${KAFKA_JSON_EVENTS_STORE_MV_DDL:?Missing KAFKA_JSON_EVENTS_STORE_MV_DDL (run: source scripts/source_env.sh)}"
: "${SCHEMA_REGISTRY_URL:?Missing SCHEMA_REGISTRY_URL (run: source scripts/source_env.sh)}"
: "${CLICKHOUSE_HTTP:?Missing CLICKHOUSE_HTTP (run: source scripts/source_env.sh)}"
: "${CLICKHOUSE_NODE1_HTTP:?Missing CLICKHOUSE_NODE1_HTTP (run: source scripts/source_env.sh)}"
: "${CLICKHOUSE_NODE2_HTTP:?Missing CLICKHOUSE_NODE2_HTTP (run: source scripts/source_env.sh)}"
: "${BOOTSTRAP_SERVERS_INTERNAL:?Missing BOOTSTRAP_SERVERS_INTERNAL (run: source scripts/source_env.sh)}"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }
}

require curl
require docker
require jq

create_client_properties() {
  local container="$1"
  docker compose exec -T \
    -e KAFKA_CLIENT_SASL_USERNAME="${KAFKA_CLIENT_SASL_USERNAME}" \
    -e KAFKA_CLIENT_SASL_PASSWORD="${KAFKA_CLIENT_SASL_PASSWORD}" \
    "${container}" bash -ec 'cat > /tmp/client.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_CLIENT_SASL_USERNAME}" password="${KAFKA_CLIENT_SASL_PASSWORD}";
EOF'
}

echo "0) Prepare Kafka client config inside kafka-broker-1"
create_client_properties kafka-broker-1

echo "1) Register JSON schema for ${KAFKA_JSON_EVENTS_TOPIC}"
schema_payload="$(mktemp)"
jq -n --slurpfile schema "${KAFKA_JSON_EVENTS_SCHEMA_FILE}" \
  '{schemaType:"JSON", schema: ($schema[0] | tojson)}' > "${schema_payload}"
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data @"${schema_payload}" \
  "${SCHEMA_REGISTRY_URL}/subjects/${KAFKA_JSON_EVENTS_SUBJECT}/versions" | jq .
rm -f "${schema_payload}"

echo "2) Apply ClickHouse DDLs (Kafka internal DB + JSON tables)"
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_INTERNAL_DB_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_JSON_EVENTS_TABLE_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_JSON_EVENTS_STORE_TABLE_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_JSON_EVENTS_STORE_MV_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null

echo "3) Confirm JSON Kafka engine table exists on both nodes"
json_table_exists=false
for _ in {1..12}; do
  node1="$(curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_NODE1_HTTP}/?query=EXISTS+TABLE+${KAFKA_INTERNAL_DB}.${KAFKA_JSON_EVENTS_TABLE}")"
  node2="$(curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_NODE2_HTTP}/?query=EXISTS+TABLE+${KAFKA_INTERNAL_DB}.${KAFKA_JSON_EVENTS_TABLE}")"
  if [[ "${node1}" == "1" && "${node2}" == "1" ]]; then
    json_table_exists=true
    break
  fi
  sleep 2
done
if [[ "${json_table_exists}" != "true" ]]; then
  echo "ClickHouse table ${KAFKA_JSON_EVENTS_TABLE} did not appear on both nodes; check DDL replication." >&2
  exit 1
fi

echo "4) Confirm JSON store table exists on both nodes"
json_store_exists=false
for _ in {1..12}; do
  node1="$(curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_NODE1_HTTP}/?query=EXISTS+TABLE+default.${KAFKA_JSON_EVENTS_STORE_TABLE}")"
  node2="$(curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_NODE2_HTTP}/?query=EXISTS+TABLE+default.${KAFKA_JSON_EVENTS_STORE_TABLE}")"
  if [[ "${node1}" == "1" && "${node2}" == "1" ]]; then
    json_store_exists=true
    break
  fi
  sleep 2
done
if [[ "${json_store_exists}" != "true" ]]; then
  echo "ClickHouse table ${KAFKA_JSON_EVENTS_STORE_TABLE} did not appear on both nodes; check DDL replication." >&2
  exit 1
fi

echo "5) Ensure Kafka topic exists (${KAFKA_JSON_EVENTS_TOPIC})"
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --replication-factor 3 --partitions 1

echo "6) Produce JSON sample message"
json_ts="$(date -u +"%Y-%m-%d %H:%M:%S")"
printf '{"id":%s,"source":"smoke-json","ts":"%s","payload":"hello-json"}\n' \
  "101" "${json_ts}" | docker compose exec -T \
  kafka-broker-1 kafka-console-producer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --producer.config /tmp/client.properties

echo "7) Consume one JSON message from ${KAFKA_JSON_EVENTS_TOPIC}"
docker compose exec -T \
  kafka-broker-1 kafka-console-consumer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --consumer.config /tmp/client.properties \
  --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 10000 || true

echo "8) Verify JSON store table via HAProxy (${KAFKA_JSON_EVENTS_STORE_TABLE})"
json_rows="0"
for _ in {1..12}; do
  json_rows="$(curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_HTTP}/?query=SELECT+count()+FROM+${KAFKA_JSON_EVENTS_STORE_TABLE}")"
  if [[ "${json_rows}" != "0" ]]; then
    break
  fi
  sleep 2
done
curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+*+FROM+${KAFKA_JSON_EVENTS_STORE_TABLE}+ORDER+BY+ts+DESC+LIMIT+1"
