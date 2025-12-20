# Kafka → ClickHouse (Local Data Pipeline)

This repository contains a **step-by-step, Docker Compose–based local data pipeline** built incrementally.

The end goal is a **Kafka → ClickHouse** pipeline with:

* explicit ingestion (Kafka Connect),
* schema discipline (Schema Registry),
* persistence and restart safety,
* and later: authentication and least-privilege access.

The stack is intentionally built **in small, reviewable steps** to avoid hidden coupling and “works by accident” setups.

---

## Scope

**In scope**

* Local development only (Docker Compose)
* Local Kubernetes migration (kind) in Step III
* Kafka, Schema Registry, Kafka Connect
* ClickHouse as analytical sink
* Explicit configuration and persistence
* Reproducible startup and smoke tests

**Out of scope**

* Production Kubernetes, managed services, and HA sizing
* Production sizing and HA
* Full TLS/mTLS (added later only if needed)
* Application-level business logic

---

## Repository structure

```
.
├── docker-compose.yml     # Incrementally built Compose file
├── .env.example           # Non-sensitive defaults only
├── README.md              # This document
├── configs/               # Mounted service configs (Kafka, Connect, ClickHouse)
├── sql/                   # ClickHouse schemas and setup scripts
└── scripts/               # Helper scripts (optional, documented)
```

---

## Design principles

* **One step = one small, testable change**
* **State is persistent by default**
* **Config is mounted, not baked into images**
* **Explicit over implicit** (topics, schemas, tables)
* **Security added incrementally, not bolted on**

---

## Steps

* Step I — Build the Docker Compose pipeline from zero
* Step II — Add authentication and secrets safely
* Step III — Migrate to a local Kubernetes cluster

---

## How to work with this repo

* Each commit introduces **one clear deliverable**
* The stack should be runnable and verifiable at every step
* If something breaks, it should be obvious *which step caused it*

This repository is meant to be read **commit-by-commit**, not just “used”.
