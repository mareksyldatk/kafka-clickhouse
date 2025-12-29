-- Kafka engine table for ingest-only reads from Kafka (JSON).
-- Update topic/credentials/format to match your environment before running.

CREATE TABLE IF NOT EXISTS kafka_internal.kafka_json_events ON CLUSTER clickhouse_cluster (
    id UInt64,
    source String,
    ts DateTime64(3, 'UTC'),
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka-broker-1:9093,kafka-broker-2:9093,kafka-broker-3:9093',
    kafka_topic_list = 'kafka-json-events',
    kafka_group_name = 'clickhouse-kafka-json-events',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_security_protocol = 'SASL_PLAINTEXT',
    kafka_sasl_mechanism = 'PLAIN',
    kafka_sasl_username = 'client',
    kafka_sasl_password = 'change_me';
