-- Persisted JSON events for stable querying (Kafka engine -> MergeTree).
-- Standalone storage table; the materialized view handles ingestion.

CREATE TABLE IF NOT EXISTS kafka_json_events_store ON CLUSTER clickhouse_cluster (
    id UInt64,
    source String,
    ts DateTime64(3, 'UTC'),
    payload String
) ENGINE = ReplicatedMergeTree('/clickhouse/{shard}/kafka_json_events_store', '{replica}')
ORDER BY (ts, id);
