#!/usr/bin/env python3
import os
import sys
from confluent_kafka import DeserializingConsumer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer
from confluent_kafka.serialization import MessageField, SerializationContext

BOOTSTRAP = os.getenv("BOOTSTRAP_SERVERS")
SCHEMA_REGISTRY_URL = os.getenv("SCHEMA_REGISTRY_URL")
TOPIC = os.getenv("TOPIC")
GROUP_ID = os.getenv("GROUP_ID")
MAX_MESSAGES_RAW = os.getenv("MAX_MESSAGES")
SASL_USERNAME = os.getenv("KAFKA_CLIENT_SASL_USERNAME")
SASL_PASSWORD = os.getenv("KAFKA_CLIENT_SASL_PASSWORD")


def main() -> int:
    missing = [
        name
        for name, value in {
            "BOOTSTRAP_SERVERS": BOOTSTRAP,
            "SCHEMA_REGISTRY_URL": SCHEMA_REGISTRY_URL,
            "TOPIC": TOPIC,
            "GROUP_ID": GROUP_ID,
            "MAX_MESSAGES": MAX_MESSAGES_RAW,
            "KAFKA_CLIENT_SASL_USERNAME": SASL_USERNAME,
            "KAFKA_CLIENT_SASL_PASSWORD": SASL_PASSWORD,
        }.items()
        if not value
    ]
    if missing:
        print(
            "Missing required environment variables: "
            + ", ".join(missing),
            file=sys.stderr,
        )
        return 1
    try:
        max_messages = int(MAX_MESSAGES_RAW)
    except ValueError:
        print("MAX_MESSAGES must be an integer.", file=sys.stderr)
        return 1

    schema_registry = SchemaRegistryClient({"url": SCHEMA_REGISTRY_URL})
    deserializer = AvroDeserializer(schema_registry)

    config = {
        "bootstrap.servers": BOOTSTRAP,
        "group.id": GROUP_ID,
        "auto.offset.reset": "latest",
        "value.deserializer": deserializer,
        "key.deserializer": None,
    }
    config.update(
        {
            "security.protocol": "SASL_PLAINTEXT",
            "sasl.mechanism": "PLAIN",
            "sasl.username": SASL_USERNAME,
            "sasl.password": SASL_PASSWORD,
        }
    )
    consumer = DeserializingConsumer(config)

    consumer.subscribe([TOPIC])

    received = 0
    try:
        while received < max_messages:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print(msg.error(), file=sys.stderr)
                continue

            ctx = SerializationContext(TOPIC, MessageField.VALUE)
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
