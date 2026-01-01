#!/usr/bin/env python
"""
Minimal ClickHouse query helper for local dev using clickhouse-connect.

Reads CLICKHOUSE_HTTP, CLICKHOUSE_READER_USER, CLICKHOUSE_READER_PASSWORD,
KAFKA_AVRO_EVENTS_TABLE, LIMIT and prints the result rows.
"""
import os
import sys
from urllib.parse import urlparse

import clickhouse_connect


CLICKHOUSE_HTTP = os.getenv("CLICKHOUSE_HTTP")
CLICKHOUSE_USER = os.getenv("CLICKHOUSE_READER_USER")
CLICKHOUSE_PASSWORD = os.getenv("CLICKHOUSE_READER_PASSWORD")
KAFKA_AVRO_EVENTS_TABLE = os.getenv("KAFKA_AVRO_EVENTS_TABLE")
LIMIT_RAW = os.getenv("LIMIT")


def get_client():
    parsed = urlparse(CLICKHOUSE_HTTP)
    host = parsed.hostname
    port = parsed.port
    secure = parsed.scheme == "https"
    if not host or port is None:
        raise ValueError("CLICKHOUSE_HTTP must include host and port.")
    return clickhouse_connect.get_client(
        host=host,
        port=port,
        username=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD,
        secure=secure,
    )


def main() -> int:
    missing = [
        name
        for name, value in {
            "CLICKHOUSE_HTTP": CLICKHOUSE_HTTP,
            "CLICKHOUSE_READER_USER": CLICKHOUSE_USER,
            "CLICKHOUSE_READER_PASSWORD": CLICKHOUSE_PASSWORD,
            "KAFKA_AVRO_EVENTS_TABLE": KAFKA_AVRO_EVENTS_TABLE,
            "LIMIT": LIMIT_RAW,
        }.items()
        if not value
    ]
    if missing:
        print(
            "Missing required environment variables: " + ", ".join(missing),
            file=sys.stderr,
        )
        return 1
    try:
        limit = int(LIMIT_RAW)
    except ValueError:
        print("LIMIT must be an integer.", file=sys.stderr)
        return 1
    try:
        client = get_client()
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    query = (
        f"SELECT * FROM {KAFKA_AVRO_EVENTS_TABLE} ORDER BY id LIMIT {limit}"
    )
    result = client.query(query)
    # Print header then rows as TSV for readability
    headers = result.column_names
    rows = result.result_rows
    print("\t".join(headers))
    for row in rows:
        print("\t".join(str(x) for x in row))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
