#!/usr/bin/env python3
import json
import sys
from confluent_kafka import Producer

from kafka_common import parse_int, producer_config, require_env
from util_time import clickhouse_timestamp


def main() -> int:
    env = require_env(
        [
            "BOOTSTRAP_SERVERS",
            "KAFKA_JSON_EVENTS_TOPIC",
            "MESSAGE_ID",
            "KAFKA_CLIENT_SASL_USERNAME",
            "KAFKA_CLIENT_SASL_PASSWORD",
        ]
    )
    if env is None:
        return 1

    message_id = parse_int("MESSAGE_ID", env["MESSAGE_ID"])
    if message_id is None:
        return 1

    config = producer_config(
        env["BOOTSTRAP_SERVERS"],
        env["KAFKA_CLIENT_SASL_USERNAME"],
        env["KAFKA_CLIENT_SASL_PASSWORD"],
    )
    producer = Producer(config)
    ts = clickhouse_timestamp()
    value = {
        "id": message_id,
        "source": "python-json-producer",
        "ts": ts,
        "payload": "hello-json",
    }

    producer.produce(topic=env["KAFKA_JSON_EVENTS_TOPIC"], value=json.dumps(value))
    producer.flush()

    print(
        "Produced 1 record to "
        f"{env['KAFKA_JSON_EVENTS_TOPIC']} with id={message_id} ts={ts}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
