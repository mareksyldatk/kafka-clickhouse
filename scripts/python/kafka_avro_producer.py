#!/usr/bin/env python3
import sys
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import MessageField, SerializationContext

from kafka_common import parse_int, producer_config, require_env
from util_time import utc_timestamp

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
    env = require_env(
        [
            "BOOTSTRAP_SERVERS",
            "SCHEMA_REGISTRY_URL",
            "KAFKA_AVRO_EVENTS_TOPIC",
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

    schema_registry = SchemaRegistryClient({"url": env["SCHEMA_REGISTRY_URL"]})
    serializer = AvroSerializer(schema_registry, SCHEMA_STR, dict_to_avro)

    config = producer_config(
        env["BOOTSTRAP_SERVERS"],
        env["KAFKA_CLIENT_SASL_USERNAME"],
        env["KAFKA_CLIENT_SASL_PASSWORD"],
    )
    producer = Producer(config)
    ts = utc_timestamp()
    value = {
        "id": message_id,
        "source": "python-avro-producer",
        "ts": ts,
        "payload": "hello",
    }

    payload = serializer(
        value,
        SerializationContext(env["KAFKA_AVRO_EVENTS_TOPIC"], MessageField.VALUE),
    )
    producer.produce(topic=env["KAFKA_AVRO_EVENTS_TOPIC"], value=payload)
    producer.flush()

    print(
        "Produced 1 record to "
        f"{env['KAFKA_AVRO_EVENTS_TOPIC']} with id={message_id} ts={ts}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
