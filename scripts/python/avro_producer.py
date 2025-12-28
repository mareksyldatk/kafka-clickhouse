#!/usr/bin/env python3
import os
import sys
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import MessageField, SerializationContext

from util_time import utc_timestamp
BOOTSTRAP = os.getenv("BOOTSTRAP_SERVERS")
SCHEMA_REGISTRY_URL = os.getenv("SCHEMA_REGISTRY_URL")
TOPIC = os.getenv("TOPIC")
MESSAGE_ID = os.getenv("MESSAGE_ID")
SASL_USERNAME = os.getenv("KAFKA_CLIENT_SASL_USERNAME")
SASL_PASSWORD = os.getenv("KAFKA_CLIENT_SASL_PASSWORD")

SCHEMA_STR = """
{
  "type": "record",
  "name": "KafkaEvent",
  "namespace": "example",
  "fields": [
    {"name": "id", "type": "long"},
    {"name": "source", "type": "string"},
    {"name": "ts", "type": "string"},
    {"name": "payload", "type": "string"}
  ]
}
"""


def dict_to_avro(obj, ctx):
    return obj


def main() -> int:
    missing = []
    required = {
        "BOOTSTRAP_SERVERS": BOOTSTRAP,
        "SCHEMA_REGISTRY_URL": SCHEMA_REGISTRY_URL,
        "TOPIC": TOPIC,
        "MESSAGE_ID": MESSAGE_ID,
        "KAFKA_CLIENT_SASL_USERNAME": SASL_USERNAME,
        "KAFKA_CLIENT_SASL_PASSWORD": SASL_PASSWORD,
    }
    for name, value in required.items():
        if not value:
            missing.append(name)
    if missing:
        print(
            "Missing required environment variables: "
            + ", ".join(missing),
            file=sys.stderr,
        )
        return 1

    schema_registry = SchemaRegistryClient({"url": SCHEMA_REGISTRY_URL})
    serializer = AvroSerializer(schema_registry, SCHEMA_STR, dict_to_avro)

    config = {"bootstrap.servers": BOOTSTRAP}
    config.update(
        {
            "security.protocol": "SASL_PLAINTEXT",
            "sasl.mechanism": "PLAIN",
            "sasl.username": SASL_USERNAME,
            "sasl.password": SASL_PASSWORD,
        }
    )
    producer = Producer(config)
    ts = utc_timestamp()
    value = {
        "id": int(MESSAGE_ID),
        "source": "python-producer",
        "ts": ts,
        "payload": "hello",
    }

    payload = serializer(value, SerializationContext(TOPIC, MessageField.VALUE))
    producer.produce(topic=TOPIC, value=payload)
    producer.flush()

    print(f"Produced 1 record to {TOPIC} with id={MESSAGE_ID} ts={ts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
