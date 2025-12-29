#!/usr/bin/env bash
set -euo pipefail

# Non-interactive end-to-end smoke test:
# Schema Registry → Kafka (Avro) → Kafka Connect → ClickHouse (through HAProxy).
#
# Prereqs:
# - Stack is up and healthy (kafka, schema-registry, kafka-connect, clickhouse-keeper, clickhouse-1/2, haproxy).
# - Connector config exists at configs/connect/clickhouse-sink.json and uses Avro converters.
# - clickhouse_kafka_avro_events.sql matches the payload schema below.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${CLICKHOUSE_USER:?Missing CLICKHOUSE_USER in .env}"
: "${CLICKHOUSE_PASSWORD:?Missing CLICKHOUSE_PASSWORD in .env}"
: "${KAFKA_CLIENT_SASL_USERNAME:?Missing KAFKA_CLIENT_SASL_USERNAME in .env}"
: "${KAFKA_CLIENT_SASL_PASSWORD:?Missing KAFKA_CLIENT_SASL_PASSWORD in .env}"
: "${CONNECTOR_CONFIG:?Missing CONNECTOR_CONFIG in .env}"
: "${CONNECTOR_NAME:?Missing CONNECTOR_NAME in .env}"
: "${KAFKA_AVRO_EVENTS_TABLE_DDL:?Missing KAFKA_AVRO_EVENTS_TABLE_DDL in .env}"
: "${KAFKA_AVRO_EVENTS_TOPIC:?Missing KAFKA_AVRO_EVENTS_TOPIC in .env}"
: "${KAFKA_AVRO_EVENTS_TABLE:?Missing KAFKA_AVRO_EVENTS_TABLE in .env}"
: "${KAFKA_AVRO_EVENTS_SUBJECT:?Missing KAFKA_AVRO_EVENTS_SUBJECT in .env}"
: "${KAFKA_INTERNAL_DB:?Missing KAFKA_INTERNAL_DB in .env}"
: "${KAFKA_INTERNAL_DB_DDL:?Missing KAFKA_INTERNAL_DB_DDL in .env}"
: "${KAFKA_JSON_EVENTS_TABLE:?Missing KAFKA_JSON_EVENTS_TABLE in .env}"
: "${KAFKA_JSON_EVENTS_TABLE_DDL:?Missing KAFKA_JSON_EVENTS_TABLE_DDL in .env}"
: "${KAFKA_JSON_EVENTS_TOPIC:?Missing KAFKA_JSON_EVENTS_TOPIC in .env}"
: "${KAFKA_JSON_EVENTS_STORE_TABLE:?Missing KAFKA_JSON_EVENTS_STORE_TABLE in .env}"
: "${KAFKA_JSON_EVENTS_STORE_TABLE_DDL:?Missing KAFKA_JSON_EVENTS_STORE_TABLE_DDL in .env}"
: "${KAFKA_JSON_EVENTS_STORE_MV_DDL:?Missing KAFKA_JSON_EVENTS_STORE_MV_DDL in .env}"
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

create_quiet_log4j() {
  local container="$1"
  docker compose exec -T "${container}" bash -ec 'cat > /tmp/log4j.properties <<EOF
log4j.rootLogger=ERROR, stdout
log4j.appender.stdout=org.apache.log4j.ConsoleAppender
log4j.appender.stdout.Target=System.out
log4j.appender.stdout.layout=org.apache.log4j.PatternLayout
log4j.appender.stdout.layout.ConversionPattern=%d{ISO8601} %-5p %c:%L - %m%n
EOF'
}

echo "0) Prepare Kafka client config inside containers"
create_client_properties kafka-broker-1
create_client_properties schema-registry
create_quiet_log4j schema-registry

echo "1) Apply ClickHouse DDLs (Kafka internal DB + tables)"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_INTERNAL_DB_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_AVRO_EVENTS_TABLE_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_JSON_EVENTS_TABLE_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_JSON_EVENTS_STORE_TABLE_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  -X POST --data-binary @"${KAFKA_JSON_EVENTS_STORE_MV_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null

echo "1a) Confirm Avro table exists on both nodes"
table_exists=false
for _ in {1..12}; do
  node1="$(curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
    "${CLICKHOUSE_NODE1_HTTP}/?query=EXISTS+TABLE+default.${KAFKA_AVRO_EVENTS_TABLE}")"
  node2="$(curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
    "${CLICKHOUSE_NODE2_HTTP}/?query=EXISTS+TABLE+default.${KAFKA_AVRO_EVENTS_TABLE}")"
  if [[ "${node1}" == "1" && "${node2}" == "1" ]]; then
    table_exists=true
    break
  fi
  sleep 2
done
if [[ "${table_exists}" != "true" ]]; then
  echo "ClickHouse table ${KAFKA_AVRO_EVENTS_TABLE} did not appear on both nodes; check DDL replication." >&2
  exit 1
fi

echo "1b) Confirm JSON Kafka engine table exists on both nodes"
json_table_exists=false
for _ in {1..12}; do
  node1="$(curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
    "${CLICKHOUSE_NODE1_HTTP}/?query=EXISTS+TABLE+${KAFKA_INTERNAL_DB}.${KAFKA_JSON_EVENTS_TABLE}")"
  node2="$(curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
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

echo "1c) Confirm JSON store table exists on both nodes"
json_store_exists=false
for _ in {1..12}; do
  node1="$(curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
    "${CLICKHOUSE_NODE1_HTTP}/?query=EXISTS+TABLE+default.${KAFKA_JSON_EVENTS_STORE_TABLE}")"
  node2="$(curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
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

echo "3) Register Avro schema for ${KAFKA_AVRO_EVENTS_TOPIC}"
SCHEMA_BODY="$(mktemp)"
printf '{"schema":"%s"}' "$(printf '%s' "${AVRO_SCHEMA}" | sed 's/"/\\"/g')" > "${SCHEMA_BODY}"
curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data @"${SCHEMA_BODY}" \
  "${SCHEMA_REGISTRY_URL}/subjects/${KAFKA_AVRO_EVENTS_SUBJECT}/versions" | jq .
rm -f "${SCHEMA_BODY}"

echo "4) Ensure Kafka topics exist (${KAFKA_AVRO_EVENTS_TOPIC}, ${KAFKA_JSON_EVENTS_TOPIC})"
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic "${KAFKA_AVRO_EVENTS_TOPIC}" \
  --replication-factor 3 --partitions 1
docker compose exec \
  kafka-broker-1 kafka-topics \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic "${KAFKA_JSON_EVENTS_TOPIC}" \
  --replication-factor 3 --partitions 1

echo "5) Produce Avro sample messages (topic: ${KAFKA_AVRO_EVENTS_TOPIC}, ids: 1..5, payloads: hello world foo bar baz)"
payloads=(hello world foo bar baz)
for id in 1 2 3 4 5; do
  ts="$(./scripts/set_message_ts.sh)"
  payload="${payloads[$((id - 1))]}"
  printf '{"id":%s,"source":"smoke","ts":"%s","payload":"%s"}\n' "${id}" "${ts}" "${payload}"
  sleep 1
done | docker compose exec -T \
  schema-registry kafka-avro-console-producer \
  --bootstrap-server "${BOOTSTRAP_SERVERS_INTERNAL}" \
  --topic "${KAFKA_AVRO_EVENTS_TOPIC}" \
  --property schema.registry.url="${SCHEMA_REGISTRY_URL_INTERNAL}" \
  --property value.schema='{"type":"record","name":"KafkaEvent","namespace":"example","fields":[{"name":"id","type":"long"},{"name":"source","type":"string"},{"name":"ts","type":"string"},{"name":"payload","type":"string"}]}' \
  --producer.config /tmp/client.properties \
  --producer-property enable.metrics.push=false

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
  --max-messages 1

echo "8) Verify Avro data landed in ClickHouse (${KAFKA_AVRO_EVENTS_TABLE})"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+count(),+min(id),+max(id)+FROM+${KAFKA_AVRO_EVENTS_TABLE}"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+*+FROM+${KAFKA_AVRO_EVENTS_TABLE}+ORDER+BY+ts+DESC+LIMIT+5"

echo "9) Verify JSON store table via HAProxy (${KAFKA_JSON_EVENTS_STORE_TABLE})"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+*+FROM+${KAFKA_JSON_EVENTS_STORE_TABLE}+ORDER+BY+ts+DESC+LIMIT+1"

echo "Smoke test completed."
