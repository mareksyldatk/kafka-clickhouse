import os
import sys


def require_env(names):
    values = {name: os.getenv(name) for name in names}
    missing = [name for name, value in values.items() if not value]
    if missing:
        print(
            "Missing required environment variables: " + ", ".join(missing),
            file=sys.stderr,
        )
        return None
    return values


def parse_int(name, value):
    try:
        return int(value)
    except ValueError:
        print(f"{name} must be an integer.", file=sys.stderr)
        return None


def sasl_config(username, password):
    return {
        "security.protocol": "SASL_PLAINTEXT",
        "sasl.mechanism": "PLAIN",
        "sasl.username": username,
        "sasl.password": password,
    }


def producer_config(bootstrap, username, password):
    config = {"bootstrap.servers": bootstrap}
    config.update(sasl_config(username, password))
    return config


def consumer_config(bootstrap, group_id, username, password):
    config = {
        "bootstrap.servers": bootstrap,
        "group.id": group_id,
        "auto.offset.reset": "latest",
    }
    config.update(sasl_config(username, password))
    return config
