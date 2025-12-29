#!/usr/bin/env python3
import sys
from confluent_kafka import DeserializingConsumer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer
from confluent_kafka.serialization import MessageField, SerializationContext

from kafka_common import consumer_config, parse_int, require_env


def main() -> int:
    env = require_env(
        [
            "BOOTSTRAP_SERVERS",
            "SCHEMA_REGISTRY_URL",
            "KAFKA_AVRO_EVENTS_TOPIC",
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

    schema_registry = SchemaRegistryClient({"url": env["SCHEMA_REGISTRY_URL"]})
    deserializer = AvroDeserializer(schema_registry)

    config = consumer_config(
        env["BOOTSTRAP_SERVERS"],
        env["GROUP_ID"],
        env["KAFKA_CLIENT_SASL_USERNAME"],
        env["KAFKA_CLIENT_SASL_PASSWORD"],
    )
    config.update(
        {
            "value.deserializer": deserializer,
            "key.deserializer": None,
        }
    )
    consumer = DeserializingConsumer(config)

    consumer.subscribe([env["KAFKA_AVRO_EVENTS_TOPIC"]])

    received = 0
    try:
        while received < max_messages:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print(msg.error(), file=sys.stderr)
                continue

            ctx = SerializationContext(
                env["KAFKA_AVRO_EVENTS_TOPIC"], MessageField.VALUE
            )
            value = msg.value() if msg.value() is not None else None
            if value is None:
                value = deserializer(msg.value(), ctx)
            print(value)
            received += 1
    finally:
        consumer.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
