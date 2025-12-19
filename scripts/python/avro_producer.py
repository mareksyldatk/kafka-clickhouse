#!/usr/bin/env python3
import os
import sys
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import MessageField, SerializationContext

BOOTSTRAP = os.getenv(
    "BOOTSTRAP_SERVERS",
    "localhost:19092,localhost:29092,localhost:39092",
)
SCHEMA_REGISTRY_URL = os.getenv("SCHEMA_REGISTRY_URL", "http://localhost:8081")
TOPIC = os.getenv("TOPIC", "smoke-avro")
MESSAGE_ID = os.getenv("MESSAGE_ID", "1")

SCHEMA_STR = """
{
  "type": "record",
  "name": "SmokeAvro",
  "namespace": "example",
  "fields": [
    {"name": "id", "type": "string"}
  ]
}
"""


def dict_to_avro(obj, ctx):
    return obj


def main() -> int:
    schema_registry = SchemaRegistryClient({"url": SCHEMA_REGISTRY_URL})
    serializer = AvroSerializer(schema_registry, SCHEMA_STR, dict_to_avro)

    producer = Producer({"bootstrap.servers": BOOTSTRAP})
    value = {"id": MESSAGE_ID}

    payload = serializer(value, SerializationContext(TOPIC, MessageField.VALUE))
    producer.produce(topic=TOPIC, value=payload)
    producer.flush()

    print(f"Produced 1 record to {TOPIC} with id={MESSAGE_ID}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
