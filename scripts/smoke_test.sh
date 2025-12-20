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

if [[ -f .env ]]; then
  set -a
  # Export vars from .env for downstream docker/curl commands.
  # shellcheck disable=SC1091
  source .env
  set +a
fi

CLICKHOUSE_USER="${CLICKHOUSE_USER:-admin}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-clickhouse}"
CONNECTOR_CONFIG="${CONNECTOR_CONFIG:-configs/connect/clickhouse-sink.json}"
TABLE_DDL="${TABLE_DDL:-sql/ddl/clickhouse_kafka_sink.sql}"
TOPIC="${TOPIC:-kafka-events}"
TABLE="${TABLE:-kafka_events}"
SCHEMA_SUBJECT="${SCHEMA_SUBJECT:-${TOPIC}-value}"
SCHEMA_REGISTRY_URL="${SCHEMA_REGISTRY_URL:-http://localhost:8081}"
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CLICKHOUSE_HTTP="${CLICKHOUSE_HTTP:-http://localhost:18123}"
AVRO_SCHEMA='{"type":"record","name":"KafkaEvent","namespace":"example","fields":[{"name":"id","type":"long"},{"name":"source","type":"string"},{"name":"ts","type":"string"},{"name":"payload","type":"string"}]}'
KAFKA_CLIENT_SASL_USERNAME="${KAFKA_CLIENT_SASL_USERNAME:-}"
KAFKA_CLIENT_SASL_PASSWORD="${KAFKA_CLIENT_SASL_PASSWORD:-}"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }
}

require curl
require jq
require docker

if [[ -z "${KAFKA_CLIENT_SASL_USERNAME}" || -z "${KAFKA_CLIENT_SASL_PASSWORD}" ]]; then
  echo "Missing SASL client credentials. Set KAFKA_CLIENT_SASL_USERNAME and KAFKA_CLIENT_SASL_PASSWORD." >&2
  exit 1
fi

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

echo "1) Apply ClickHouse sink connector config (${CONNECTOR_CONFIG})"
curl -s -X PUT -H "Content-Type: application/json" \
  --data @"${CONNECTOR_CONFIG}" \
  "${CONNECT_URL}/connectors/clickhouse-sink/config" | jq .

echo "2) Ensure ClickHouse table exists (ON CLUSTER)"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  -X POST --data-binary @"${TABLE_DDL}" \
  "${CLICKHOUSE_HTTP}/?query=" >/dev/null

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
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --command-config /tmp/client.properties \
  --create --if-not-exists --topic "${TOPIC}" \
  --replication-factor 3 --partitions 1

echo "5) Produce Avro sample messages"
for id in 1 2 3 4 5; do
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  payloads=(hello world foo bar baz)
  payload="${payloads[$((id - 1))]}"
  printf '{"id":%s,"source":"smoke","ts":"%s","payload":"%s"}\n' "${id}" "${ts}" "${payload}"
  sleep 1
done | docker compose exec -T \
  schema-registry kafka-avro-console-producer \
  --bootstrap-server kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093 \
  --topic "${TOPIC}" \
  --property schema.registry.url=http://schema-registry:8081 \
  --property value.schema='{"type":"record","name":"KafkaEvent","namespace":"example","fields":[{"name":"id","type":"long"},{"name":"source","type":"string"},{"name":"ts","type":"string"},{"name":"payload","type":"string"}]}' \
  --producer.config /tmp/client.properties \
  --producer-property enable.metrics.push=false

echo "6) Verify data landed in ClickHouse"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+count(),+min(id),+max(id)+FROM+${TABLE}"
curl -sS -u "${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}" \
  "${CLICKHOUSE_HTTP}/?query=SELECT+*+FROM+${TABLE}+ORDER+BY+ts+DESC+LIMIT+5"

echo "Smoke test completed."
