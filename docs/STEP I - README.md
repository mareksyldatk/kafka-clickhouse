# Kafka → ClickHouse (Step I)

### Incremental Docker Compose Roadmap (Codex Prompts + Rationale)

---

## Phase 0 — Foundation (prevent entropy early)

### Commit 1 — Repository scaffold

**Prompt**

```text
Create a minimal repository scaffold for a Docker Compose–based data pipeline.
Add an empty docker-compose.yml, README.md, .gitignore, and directories: configs/, sql/, scripts/.
Do not add any services yet.
Keep everything minimal and documented.
```

**Why**

* Prevents “everything in one YAML” chaos later
* Establishes predictable mount points for configs and SQL
* Makes each future commit small and reviewable

---

### Commit 2 — Environment defaults

**Prompt**

```text
Add .env.example with documented defaults (ports, container names).
Update README to explain how .env is used and what is safe to put there.
Do not add secrets or services.
```

**Why**

* Separates *configuration* from *structure*
* Avoids hardcoded ports and names
* Makes local runs reproducible across machines

---

## Phase 1 — Minimal Kafka (fast feedback loop)

### Commit 3 — Kafka in KRaft mode

**Prompt**

```text
Add a single Kafka broker running in KRaft mode to docker-compose.yml.
No ZooKeeper.
Expose a local listener usable from the host.
Keep configuration minimal and readable.
```

**Why**

* Smallest possible Kafka that actually runs
* Proves Docker networking + port exposure
* Avoids ZooKeeper complexity

---

### Commit 4 — Healthcheck + smoke test

**Prompt**

```text
Add a healthcheck to the Kafka service.
Update README with simple CLI smoke-test commands: create topic, produce, consume.
Do not add persistence yet.
```

**Why**

* Defines what “Kafka is healthy” means
* Gives you a deterministic success signal
* Prevents guessing whether failures are infra or usage

---

### Commit 5 — Kafka persistence

**Prompt**

```text
Add a named Docker volume for Kafka data so topics persist across restarts.
Document how to verify persistence in the README.
```

**Why**

* Restart safety is non-negotiable for pipelines
* Forces you to treat Kafka as stateful from day one
* Prevents false confidence from ephemeral setups

---

## Phase 2 — Schema Registry (data contract layer)

### Commit 6 — Schema Registry service

**Prompt**

```text
Add Schema Registry service connected to Kafka.
Expose it locally.
Add a simple README check to verify it is running (list subjects).
```

**Why**

* Introduces schema discipline early
* Separates data contracts from producers/consumers
* Prevents schema chaos later in the pipeline

---

### Commit 7 — Schema workflow documentation

**Prompt**

```text
Add documentation for registering a sample schema in Schema Registry and checking compatibility.
Do not add producers or consumers yet.
```

**Why**

* Validates the schema lifecycle in isolation
* Ensures you understand compatibility before data flows
* Keeps infra and app concerns separated

---

## Phase 3 — ClickHouse (destination first)

### Commit 8 — ClickHouse service

**Prompt**

```text
Add a single-node ClickHouse service to docker-compose.
No integration yet.
Expose native and HTTP ports locally.
Keep config minimal.
```

**Why**

* Validates ClickHouse independently
* Prevents debugging ingestion + DB at the same time
* Confirms local connectivity and basic operability

---

### Commit 9 — ClickHouse persistence

**Prompt**

```text
Add a persistent volume for ClickHouse data.
Document how to verify data survives container restarts.
```

**Why**

* Makes ClickHouse a real datastore, not a toy
* Forces correct volume handling early
* Avoids silent data loss during development

---

### Commit 10 — Config mounting for ClickHouse

**Prompt**

```text
Add support for mounting ClickHouse config/user override files from configs/clickhouse/.
Include minimal example files and documentation.
```

**Why**

* Establishes the mechanism for tuning and auth later
* Avoids rebuilding images for config changes
* Keeps runtime behavior explicit and versioned

---

## Phase 4 — Kafka Connect (ingestion engine)

### Commit 11 — Kafka Connect worker

**Prompt**

```text
Add a Kafka Connect distributed worker service.
Configure required internal topics and REST API.
Do not install any connectors yet.
```

**Why**

* Kafka Connect is a platform, not just a sink
* Validates worker startup and REST interface
* Isolates Connect issues from connector issues

---

### Commit 12 — Connect internal topics

**Prompt**

```text
Ensure Kafka Connect internal topics are explicitly configured and restart-safe for a single-broker setup.
Document their purpose in README.
```

**Why**

* Connect reliability depends on these topics
* Misconfig here causes silent data loss
* Explicit config beats “magic defaults”

---

### Commit 13 — Connector installation strategy

**Prompt**

```text
Add a reproducible strategy for installing Kafka Connect plugins (volume-mounted or custom image).
Choose one approach and document why.
Do not add ClickHouse connector yet.
```

**Why**

* Connector installation is a common failure point
* Reproducibility matters more than convenience
* Locks in a clean operational pattern

---

## Phase 5 — Kafka → ClickHouse (end-to-end)

### Commit 14 — ClickHouse target table

**Prompt**

```text
Add an example ClickHouse table schema in sql/ suitable for Kafka ingestion.
Document how and when it should be created.
```

**Why**

* Explicit schemas prevent connector surprises
* Encourages schema-first thinking
* Keeps DB evolution intentional

---

### Commit 15 — ClickHouse Sink connector

**Prompt**

```text
Add a Kafka Connect ClickHouse Sink connector configuration (single topic → single table).
Provide a README command to deploy it via Connect REST API.
```

**Why**

* First true end-to-end path
* Minimal scope = easy debugging
* Proves Kafka Connect ↔ ClickHouse integration

---

### Commit 16 — End-to-end smoke test

**Prompt**

```text
Document a full end-to-end smoke test:
schema registration → produce messages → verify rows in ClickHouse.
No code changes, documentation only.
```

**Why**

* Turns the system into a repeatable check
* Becomes your regression test
* Gives confidence before adding complexity

---

# TODO: use avro schema and schema-registry to make sure ingestion schema works with table

## Phase 6 — Stability polish (still Step I)

### Commit 17 — Log hygiene

**Prompt**

```text
Improve log readability for Kafka, Connect, and ClickHouse (levels, formatting where possible).
Document where to look first when debugging.
```

**Why**

* Most pipeline debugging is log reading
* Clean logs reduce MTTR dramatically
* Prevents drowning in noise

---

### Commit 18 — Startup ordering

**Prompt**

```text
Add health-based startup ordering where supported (depends_on + healthchecks).
Ensure the stack starts reliably with a single command.
```

**Why**

* Removes race-condition flakiness
* Makes `docker compose up` deterministic
* Improves developer trust in the system

---

### Commit 19 — Operating manual

**Prompt**

```text
Finalize README with an operating manual:
start/stop/reset volumes,
add a new topic→table pipeline,
common failure modes.
```

**Why**

* Reduces tribal knowledge
* Makes the system usable by others
* Locks in the mental model of the stack

---

## End state (after Step I)

* Kafka runs in KRaft mode (no ZooKeeper) with healthchecks and documented CLI smoke tests
* Kafka, ClickHouse, and (where needed) Connect internal state are persistent across restarts
* Schema Registry and Kafka Connect are running and verified independently before end-to-end wiring
* A minimal Kafka → Connect → ClickHouse pipeline works end-to-end with a repeatable smoke test
* Startup ordering is health-based so `docker compose up` is deterministic
