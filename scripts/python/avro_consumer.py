#!/usr/bin/env python3
import os
import sys
from confluent_kafka import DeserializingConsumer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer
from confluent_kafka.serialization import MessageField, SerializationContext

BOOTSTRAP = os.getenv(
    "BOOTSTRAP_SERVERS",
    "localhost:19092,localhost:29092,localhost:39092",
)
SCHEMA_REGISTRY_URL = os.getenv("SCHEMA_REGISTRY_URL", "http://localhost:8081")
TOPIC = os.getenv("TOPIC", "smoke-avro")
GROUP_ID = os.getenv("GROUP_ID", "smoke-avro-consumer")
MAX_MESSAGES = int(os.getenv("MAX_MESSAGES", "5"))


def main() -> int:
    schema_registry = SchemaRegistryClient({"url": SCHEMA_REGISTRY_URL})
    deserializer = AvroDeserializer(schema_registry)

    consumer = DeserializingConsumer(
        {
            "bootstrap.servers": BOOTSTRAP,
            "group.id": GROUP_ID,
            "auto.offset.reset": "earliest",
            "value.deserializer": deserializer,
            "key.deserializer": None,
        }
    )

    consumer.subscribe([TOPIC])

    received = 0
    try:
        while received < MAX_MESSAGES:
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
