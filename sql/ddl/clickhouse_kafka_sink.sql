-- Example sink table for Kafka → ClickHouse ingestion (no connector wired yet).
-- Intended target for a Kafka Connect sink (e.g., clickhouse sink) to append rows.
-- Adjust column types to match your message schema before running.

CREATE TABLE IF NOT EXISTS kafka_events (
    id UInt64,
    source String,
    ts DateTime64(3, 'UTC'),
    payload String
) ENGINE = MergeTree
ORDER BY (ts, id);
