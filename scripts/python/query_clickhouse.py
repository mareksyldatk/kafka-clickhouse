#!/usr/bin/env python
"""
Minimal ClickHouse query helper for local dev using clickhouse-connect.

Reads CLICKHOUSE_HTTP (default http://localhost:18123), CLICKHOUSE_USER, CLICKHOUSE_PASSWORD,
TABLE (default kafka_events), LIMIT (default 10) and prints the result rows.
"""
import os
import sys
from urllib.parse import urlparse

import clickhouse_connect


CLICKHOUSE_HTTP = os.getenv("CLICKHOUSE_HTTP", "http://localhost:18123")
CLICKHOUSE_USER = os.getenv("CLICKHOUSE_USER", "admin")
CLICKHOUSE_PASSWORD = os.getenv("CLICKHOUSE_PASSWORD", "clickhouse")
TABLE = os.getenv("TABLE", "kafka_events")
LIMIT = int(os.getenv("LIMIT", "5"))


def get_client():
    parsed = urlparse(CLICKHOUSE_HTTP)
    host = parsed.hostname or "localhost"
    port = parsed.port or 8123
    secure = parsed.scheme == "https"
    return clickhouse_connect.get_client(
        host=host,
        port=port,
        username=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD,
        secure=secure,
    )


def main() -> int:
    client = get_client()
    query = f"SELECT * FROM {TABLE} ORDER BY id LIMIT {LIMIT}"
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
