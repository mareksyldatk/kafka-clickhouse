#!/usr/bin/env python3
import json
import sys
from confluent_kafka import Consumer

from kafka_common import consumer_config, parse_int, require_env


def main() -> int:
    env = require_env(
        [
            "BOOTSTRAP_SERVERS",
            "KAFKA_JSON_EVENTS_TOPIC",
            "GROUP_ID",
            "MAX_MESSAGES",
            "KAFKA_CLIENT_SASL_USERNAME",
            "KAFKA_CLIENT_SASL_PASSWORD",
        ]
    )
    if env is None:
        return 1

    max_messages = parse_int("MAX_MESSAGES", env["MAX_MESSAGES"])
    if max_messages is None:
        return 1

    config = consumer_config(
        env["BOOTSTRAP_SERVERS"],
        env["GROUP_ID"],
        env["KAFKA_CLIENT_SASL_USERNAME"],
        env["KAFKA_CLIENT_SASL_PASSWORD"],
    )
    consumer = Consumer(config)

    consumer.subscribe([env["KAFKA_JSON_EVENTS_TOPIC"]])

    received = 0
    try:
        while received < max_messages:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print(msg.error(), file=sys.stderr)
                continue

            raw = msg.value()
            if raw is None:
                print("null")
                received += 1
                continue
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("utf-8", errors="replace")
            try:
                print(json.loads(text))
            except json.JSONDecodeError:
                print(text)
            received += 1
    finally:
        consumer.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
