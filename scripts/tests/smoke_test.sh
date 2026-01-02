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

ch_query() {
  local query="$1"
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    "${CLICKHOUSE_HTTP}/?query=${query}"
}

ch_post_ddl() {
  local ddl_path="$1"
  curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
    -X POST --data-binary @"${ddl_path}" \
    "${CLICKHOUSE_HTTP}/?query=" >/dev/null
}

wait_for_table() {
  local db="$1"
  local table="$2"
  local label="$3"
  local exists=false
  for _ in {1..12}; do
    node1="$(curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
      "${CLICKHOUSE_NODE1_HTTP}/?query=EXISTS+TABLE+${db}.${table}")"
    node2="$(curl -sS -u "${CLICKHOUSE_ADMIN_USER}:${CLICKHOUSE_ADMIN_PASSWORD}" \
      "${CLICKHOUSE_NODE2_HTTP}/?query=EXISTS+TABLE+${db}.${table}")"
    if [[ "${node1}" == "1" && "${node2}" == "1" ]]; then
      exists=true
      break
    fi
    sleep 2
  done
  if [[ "${exists}" != "true" ]]; then
    echo "ClickHouse table ${label} did not appear on both nodes; check DDL replication." >&2
    exit 1
  fi
}

client_config_path="/etc/kafka/secrets/client.properties"

echo "1) Register JSON schema for ${KAFKA_JSON_EVENTS_TOPIC}"
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data "$(jq -n --slurpfile schema "${KAFKA_JSON_EVENTS_SCHEMA_FILE}" \
    '{schemaType:"JSON", schema: ($schema[0] | tojson)}')" \
  "${SCHEMA_REGISTRY_URL}/subjects/${KAFKA_JSON_EVENTS_SUBJECT}/versions" | jq .

echo "2) Apply ClickHouse DDLs (Kafka internal DB + JSON tables)"
ch_post_ddl "${KAFKA_INTERNAL_DB_DDL}"
ch_post_ddl "${KAFKA_JSON_EVENTS_TABLE_DDL}"
ch_post_ddl "${KAFKA_JSON_EVENTS_STORE_TABLE_DDL}"
ch_post_ddl "${KAFKA_JSON_EVENTS_STORE_MV_DDL}"

echo "3) Confirm JSON Kafka engine table exists on both nodes"
wait_for_table "${KAFKA_INTERNAL_DB}" "${KAFKA_JSON_EVENTS_TABLE}" "${KAFKA_JSON_EVENTS_TABLE}"

echo "4) Confirm JSON store table exists on both nodes"
wait_for_table "default" "${KAFKA_JSON_EVENTS_STORE_TABLE}" "${KAFKA_JSON_EVENTS_STORE_TABLE}"

echo "5) Ensure Kafka topic exists (${KAFKA_JSON_EVENTS_TOPIC})"
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config "${client_config_path}" \
  --create --if-not-exists --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --replication-factor 3 --partitions 1

echo "6) Produce JSON sample message"
json_ts="$(date -u +"%Y-%m-%d %H:%M:%S")"
printf '{"id":%s,"source":"smoke-json","ts":"%s","payload":"hello-json"}\n' \
  "101" "${json_ts}" | docker compose exec -T \
  kafka-broker-1 kafka-console-producer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --producer.config "${client_config_path}"

echo "7) Consume one JSON message from ${KAFKA_JSON_EVENTS_TOPIC}"
docker compose exec -T \
  kafka-broker-1 kafka-console-consumer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --consumer.config "${client_config_path}" \
  --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 10000 || true

echo "8) Verify JSON store table via HAProxy (${KAFKA_JSON_EVENTS_STORE_TABLE})"
json_rows="0"
for _ in {1..12}; do
  json_rows="$(ch_query "SELECT+count()+FROM+${KAFKA_JSON_EVENTS_STORE_TABLE}")"
  if [[ "${json_rows}" != "0" ]]; then
    break
  fi
  sleep 2
done
ch_query "SELECT+*+FROM+${KAFKA_JSON_EVENTS_STORE_TABLE}+ORDER+BY+ts+DESC+LIMIT+1"
