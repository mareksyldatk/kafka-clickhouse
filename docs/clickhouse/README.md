# ClickHouse Notes

Short, quick-lookup reference for common engines and replication patterns used in Clickhouse.

## Engines (quick lookup)

### MergeTree (single node storage)
- Use when you do not need replication.
- Fast OLAP storage with primary key-like sorting via `ORDER BY`.
```sql
CREATE TABLE IF NOT EXISTS kafka_events (
    id UInt64,
    source String,
    ts DateTime64(3, 'UTC'),
    payload String
)
ENGINE = MergeTree
ORDER BY (ts, id);
```
Usage example:
```sql
INSERT INTO kafka_events VALUES (1, 'app', now64(3, 'UTC'), '{"k":"v"}');
SELECT count(*) FROM kafka_events WHERE ts >= now() - INTERVAL 1 HOUR;
```

### ReplicatedMergeTree (replicated storage)
- Use for HA; requires ClickHouse Keeper or ZooKeeper.
- Same behavior as MergeTree, but replicated by shard/replica path (why: each shard's data is duplicated across replicas for failover).
```sql
CREATE TABLE IF NOT EXISTS kafka_events ON CLUSTER clickhouse_cluster (
    id UInt64,
    source String,
    ts DateTime64(3, 'UTC'),
    payload String
)
ENGINE = ReplicatedMergeTree('/clickhouse/{shard}/kafka_events', '{replica}')
ORDER BY (ts, id);
```
Usage example (same SQL as MergeTree; replication is transparent):
```sql
SELECT min(ts), max(ts), count(*) FROM kafka_events;
```

### ReplacingMergeTree (dedupe by version)
- Use when late updates arrive and you want the last version to win.
- Provide a `version` column; final row chosen during merges.
```sql
CREATE TABLE IF NOT EXISTS kafka_events (
    id UInt64,
    source String,
    ts DateTime64(3, 'UTC'),
    payload String,
    version UInt64
)
ENGINE = ReplacingMergeTree(version)
ORDER BY (id, ts);
```
Usage example:
```sql
SELECT * FROM kafka_events FINAL WHERE id = 42;
```

### SummingMergeTree (rollups)
- Use when rows with the same sorting key should aggregate numeric columns.
```sql
CREATE TABLE IF NOT EXISTS event_counts (
    source String,
    day Date,
    cnt UInt64
)
ENGINE = SummingMergeTree
ORDER BY (source, day);
```
Usage example:
```sql
INSERT INTO event_counts VALUES ('app', today(), 1);
SELECT source, day, sum(cnt) FROM event_counts GROUP BY source, day;
```

### AggregatingMergeTree (aggregate states)
- Use for pre-aggregated metrics with aggregate state types (why: stores mergeable states for fast rollups at query time).
```sql
CREATE TABLE IF NOT EXISTS event_metrics (
    source String,
    day Date,
    uniq_users AggregateFunction(uniq, UInt64)
)
ENGINE = AggregatingMergeTree
ORDER BY (source, day);
```
Usage example:
```sql
INSERT INTO event_metrics
SELECT source, toDate(ts), uniqState(id) FROM kafka_events GROUP BY source, toDate(ts);
SELECT source, day, uniqMerge(uniq_users) FROM event_metrics GROUP BY source, day;
```

### CollapsingMergeTree (pairwise collapse)
- Use when you receive explicit insert/delete pairs via a `sign` column (why: +1/-1 rows collapse into a final net state).
```sql
CREATE TABLE IF NOT EXISTS events_delta (
    id UInt64,
    ts DateTime64(3, 'UTC'),
    sign Int8
)
ENGINE = CollapsingMergeTree(sign)
ORDER BY (id, ts);
```
Usage example:
```sql
SELECT * FROM events_delta FINAL WHERE id = 1;
```

### Kafka engine (ingest-only)
- Use for reading from Kafka; not for storage.
- Typically pair with a materialized view into a MergeTree table.
```sql
CREATE TABLE kafka_events_raw (
    id UInt64,
    source String,
    ts DateTime64(3, 'UTC'),
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka-broker-1:9093',
    kafka_topic_list = 'kafka-events',
    kafka_group_name = 'clickhouse-consumers',
    kafka_format = 'JSONEachRow';
```
Usage example (materialized view sink):
```sql
CREATE MATERIALIZED VIEW mv_kafka_events TO kafka_events AS
SELECT * FROM kafka_events_raw;
```

### Distributed (query router)
- Use for querying across all shards via one logical table (why: it fans out queries to shard-local tables and merges results).
```sql
CREATE TABLE IF NOT EXISTS kafka_events_all AS kafka_events
ENGINE = Distributed(clickhouse_cluster, default, kafka_events, rand());
```
Usage example:
```sql
SELECT count(*) FROM kafka_events_all;
```

## Replication (quick lookup)

### ReplicatedMergeTree on cluster
- Create the local table on every node with `ON CLUSTER`.
- Use `{shard}` and `{replica}` placeholders in the path.
```sql
CREATE TABLE IF NOT EXISTS kafka_events ON CLUSTER clickhouse_cluster (
    id UInt64,
    source String,
    ts DateTime64(3, 'UTC'),
    payload String
)
ENGINE = ReplicatedMergeTree('/clickhouse/{shard}/kafka_events', '{replica}')
ORDER BY (ts, id);
```
Usage example:
```sql
SELECT hostName(), count(*) FROM kafka_events GROUP BY hostName();
```

### Replicated + Distributed pair (recommended pattern)
- Local `ReplicatedMergeTree` table holds data per node.
- `Distributed` table provides cluster-wide query access.
```sql
CREATE TABLE IF NOT EXISTS kafka_events_all AS kafka_events
ENGINE = Distributed(clickhouse_cluster, default, kafka_events, rand());
```
Usage example:
```sql
SELECT count(*) FROM kafka_events_all;
```

## References
- https://clickhouse.com/docs/en/engines/table-engines/mergetree-family
- https://clickhouse.com/docs/en/engines/table-engines/kafka
- https://clickhouse.com/docs/en/engines/table-engines/distributed
- https://clickhouse.com/docs/en/engines/table-engines/replication
- https://clickhouse.com/docs/en/sql-reference/statements/create/table
