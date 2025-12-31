-- Materialized view to persist Kafka JSON events into kafka_json_events_store.
-- Requires kafka_internal.kafka_json_events and kafka_json_events_store tables to exist first.

CREATE MATERIALIZED VIEW IF NOT EXISTS kafka_internal.mv_kafka_json_events_store
ON CLUSTER clickhouse_cluster
TO default.kafka_json_events_store AS
SELECT
    id,
    source,
    ts,
    payload
FROM kafka_internal.kafka_json_events;
