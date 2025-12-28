#!/usr/bin/env bash
set -euo pipefail

# Non-interactive end-to-end smoke test:
# Schema Registry → Kafka (Avro) → Kafka Connect → ClickHouse (through HAProxy).
#
# Prereqs:
# - Stack is up and healthy (kafka, schema-registry, kafka-connect, clickhouse-keeper, clickhouse-1/2, haproxy).
# - Connector config exists at configs/connect/clickhouse-sink.json and uses Avro converters.
# - clickhouse_kafka_sink.sql matches the payload schema below.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${CLICKHOUSE_USER:?Missing CLICKHOUSE_USER in .env}"
: "${CLICKHOUSE_PASSWORD:?Missing CLICKHOUSE_PASSWORD in .env}"
: "${KAFKA_CLIENT_SASL_USERNAME:?Missing KAFKA_CLIENT_SASL_USERNAME in .env}"
: "${KAFKA_CLIENT_SASL_PASSWORD:?Missing KAFKA_CLIENT_SASL_PASSWORD in .env}"
: "${CONNECTOR_CONFIG:?Missing CONNECTOR_CONFIG in .env}"
: "${CONNECTOR_NAME:?Missing CONNECTOR_NAME in .env}"
: "${TABLE_DDL:?Missing TABLE_DDL in .env}"
: "${TOPIC:?Missing TOPIC in .env}"
: "${TABLE:?Missing TABLE in .env}"
: "${SCHEMA_SUBJECT:?Missing SCHEMA_SUBJECT in .env}"
: "${SCHEMA_REGISTRY_URL:?Missing SCHEMA_REGISTRY_URL in .env}"
: "${SCHEMA_REGISTRY_URL_INTERNAL:?Missing SCHEMA_REGISTRY_URL_INTERNAL in .env}"
: "${CONNECT_URL:?Missing CONNECT_URL in .env}"
: "${CLICKHOUSE_HTTP:?Missing CLICKHOUSE_HTTP in .env}"
: "${CLICKHOUSE_NODE1_HTTP:?Missing CLICKHOUSE_NODE1_HTTP in .env}"
: "${CLICKHOUSE_NODE2_HTTP:?Missing CLICKHOUSE_NODE2_HTTP in .env}"
: "${BOOTSTRAP_SERVERS_INTERNAL:?Missing BOOTSTRAP_SERVERS_INTERNAL in .env}"
AVRO_SCHEMA='{"type":"record","name":"KafkaEvent","namespace":"example","fields":[{"name":"id","type":"long"},{"name":"source","type":"string"},{"name":"ts","type":"string"},{"name":"payload","type":"string"}]}'

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }
}

require curl
require jq
require docker

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

echo "0) Prepare Kafka client config inside containers"
create_client_properties kafka-broker-1
create_client_properties schema-registry

echo "1) Ensure ClickHouse table exists (ON CLUSTER)"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  -X POST --data-binary @"${TABLE_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null

echo "1a) Wait for ClickHouse table to exist on both nodes"
table_exists=false
for _ in {1..12}; do
  node1="$(curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
    "${CLICKHOUSE_NODE1_HTTP}/?query=EXISTS+TABLE+default.${TABLE}")"
  node2="$(curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
    "${CLICKHOUSE_NODE2_HTTP}/?query=EXISTS+TABLE+default.${TABLE}")"
  if [[ "${node1}" == "1" && "${node2}" == "1" ]]; then
    table_exists=true
    break
  fi
  sleep 2
done
if [[ "${table_exists}" != "true" ]]; then
  echo "ClickHouse table ${TABLE} did not appear on both nodes; check DDL replication." >&2
  exit 1
fi

echo "2) Apply ClickHouse sink connector config (${CONNECTOR_CONFIG})"
curl -s -X PUT -H "Content-Type: application/json" \
  --data @"${CONNECTOR_CONFIG}" \
  "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/config" | jq .

echo "2a) Wait for connector ${CONNECTOR_NAME} to be RUNNING"
connector_running='.connector.state == "RUNNING" and (.tasks | length) > 0 and all(.tasks[]; .state == "RUNNING")'
status=""
for _ in {1..12}; do
  status="$(curl -s "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/status" || true)"
  if echo "${status}" | jq -e "${connector_running}" >/dev/null; then
    break
  fi
  sleep 5
done
if ! echo "${status}" | jq -e "${connector_running}" >/dev/null; then
  echo "Connector ${CONNECTOR_NAME} is not RUNNING:" >&2
  echo "${status}" | jq . >&2
  exit 1
fi

echo "3) Register Avro schema for topic ${TOPIC}"
SCHEMA_BODY="$(mktemp)"
printf '{"schema":"%s"}' "$(printf '%s' "${AVRO_SCHEMA}" | sed 's/"/\\"/g')" > "${SCHEMA_BODY}"
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data @"${SCHEMA_BODY}" \
  "${SCHEMA_REGISTRY_URL}/subjects/${SCHEMA_SUBJECT}/versions" | jq .
rm -f "${SCHEMA_BODY}"

echo "4) Ensure Kafka topic ${TOPIC} exists"
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic "${TOPIC}" \
  --replication-factor 3 --partitions 1

echo "5) Produce Avro sample messages"
for id in 1 2 3 4 5; do
  ts="$(./scripts/set_message_ts.sh)"
  payloads=(hello world foo bar baz)
  payload="${payloads[$((id - 1))]}"
  printf '{"id":%s,"source":"smoke","ts":"%s","payload":"%s"}\n' "${id}" "${ts}" "${payload}"
  sleep 1
done | docker compose exec -T \
  schema-registry kafka-avro-console-producer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --topic "${TOPIC}" \
  --property schema.registry.url="${SCHEMA_REGISTRY_URL_INTERNAL}" \
  --property value.schema='{"type":"record","name":"KafkaEvent","namespace":"example","fields":[{"name":"id","type":"long"},{"name":"source","type":"string"},{"name":"ts","type":"string"},{"name":"payload","type":"string"}]}' \
  --producer.config /tmp/client.properties \
  --producer-property enable.metrics.push=false

echo "6) Verify data landed in ClickHouse"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+count(),+min(id),+max(id)+FROM+${TABLE}"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+*+FROM+${TABLE}+ORDER+BY+ts+DESC+LIMIT+5"

echo "Smoke test completed."
