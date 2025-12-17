# STEP II — Add security without breaking everything

## Phase 1 — Kafka auth first (smallest secure win)

### Commit 1 — Decide local security model + document it

**Prompt**

```text
Add a SECURITY.md (or README section) defining the local security model for Step II:
- Kafka: SASL/PLAIN (no SSL for local), separate users for Connect and Schema Registry
- ClickHouse: users/roles via mounted config
Document threat model and what is explicitly out of scope for local (e.g., mTLS).
No compose changes yet.
```

**Why**

* Prevents drifting into half-secure config
* Locks in a consistent plan before touching services
* Keeps local dev pragmatic (auth yes, full TLS maybe later)

---

### Commit 2 — Add Kafka JAAS config files (mounted) + placeholders

**Prompt**

```text
Create config files for Kafka SASL/PLAIN using mounted files (e.g., configs/kafka/jaas.conf and related server/client properties).
Include placeholders only (no real passwords), and document how .env provides values or how local-only secrets files are used.
Do not enable Kafka SASL yet.
```

**Why**

* Separates “files exist and mount correctly” from “auth works”
* Prevents hardcoding credentials in compose
* Makes the next change only about enabling auth

---

### Commit 3 — Enable SASL/PLAIN on Kafka listener (internal first)

**Prompt**

```text
Enable SASL/PLAIN on Kafka in docker-compose with minimal changes:
- Keep the existing listener layout
- Switch internal listener to SASL_PLAINTEXT
- Ensure broker starts with mounted JAAS config
Add a README section explaining how to validate broker startup.
Do not update any clients yet.
```

**Why**

* One variable: broker security only
* If this fails, you know it’s broker config, not clients
* Establishes the “secured broker” baseline

---

### Commit 4 — Update Schema Registry to authenticate to Kafka

**Prompt**

```text
Update Schema Registry configuration to use SASL/PLAIN to connect to Kafka.
Mount a client config file if needed.
Add a smoke test step in README (list subjects) that proves Schema Registry works under auth.
```

**Why**

* Schema Registry is a critical platform dependency
* Validates client auth path with a simple service
* Keeps failure surface narrow

---

### Commit 5 — Update Kafka Connect worker to authenticate to Kafka

**Prompt**

```text
Update Kafka Connect worker configuration to connect to Kafka using SASL/PLAIN.
Ensure Connect internal topics still work.
Add a README smoke test to verify Connect REST is up and internal topics can be created/used.
Do not deploy sink connector yet.
```

**Why**

* Connect is the “most important client”
* Verifies offsets/config/status topics under auth
* Prevents connector debugging while fixing auth

---

### Commit 6 — Re-validate end-to-end pipeline under Kafka auth

**Prompt**

```text
Update the ClickHouse sink connector deployment instructions/config (if needed) so it works with Kafka Connect under SASL/PLAIN.
Add/adjust README E2E smoke test steps to confirm Kafka→Connect→ClickHouse still works.
No new features, only security compatibility.
```

**Why**

* Confirms you didn’t break the core value path
* Ensures auth doesn’t silently stall ingestion
* “Secure and still working” is the checkpoint

---

## Phase 2 — ClickHouse auth + least privilege

### Commit 7 — Add ClickHouse user/role config files (mounted)

**Prompt**

```text
Add mounted ClickHouse user/role configuration under configs/clickhouse/:
- create a 'writer' user for Kafka Connect
- create a 'readonly' user for humans
Define least-privilege grants for the demo database/tables.
Do not enforce auth yet (keep default access for now), only add configs and documentation.
```

**Why**

* First prove config mounting + syntax
* Avoid breaking everything by enforcing auth immediately
* Makes the next commit only about turning enforcement on

---

### Commit 8 — Enforce ClickHouse authentication

**Prompt**

```text
Enable ClickHouse authentication enforcement using the mounted user config:
- disable/default user access as appropriate for local
- ensure Kafka Connect uses the 'writer' credentials
Update README connection examples for both writer and readonly.
```

**Why**

* Hard boundary: “unauthenticated access stops”
* Validates least-privilege credentials actually work
* Catches privilege mistakes early

---

### Commit 9 — Confirm least privilege (negative tests)

**Prompt**

```text
Add README tests demonstrating least privilege:
- readonly can SELECT but cannot INSERT/CREATE
- writer can INSERT into target tables but cannot DROP/ALTER unrelated objects
No code changes beyond documentation and any required grants.
```

**Why**

* Security isn’t real without negative tests
* Prevents accidental “writer is admin” setups
* Keeps privilege creep under control

---

## Phase 3 — Secrets hygiene (don’t leave passwords in .env)

### Commit 10 — Move credentials out of .env into mounted secret files (local-only)

**Prompt**

```text
Refactor to remove passwords from .env:
- keep .env for non-sensitive config only
- add local-only secret files under a clearly ignored path (e.g., secrets/…)
- update compose to mount secrets into Kafka/Connect/Schema Registry/ClickHouse
Add .gitignore rules and README instructions for creating secrets locally.
```

**Why**

* Prevents accidental credential commits
* Matches how you’ll do it later in K8s/CI
* Keeps local setup safe by default

---

### Commit 11 — Standardize client configs for Kafka auth

**Prompt**

```text
Standardize Kafka client auth configuration across services:
- schema registry client config
- connect worker client config
- any CLI/testing configs
Ensure they all reference the same mounted patterns and docs.
```

**Why**

* Reduces duplicated, inconsistent auth config
* Makes future changes (e.g., TLS) easier
* Eliminates “one service works, one doesn’t” drift

---

## Phase 4 — Optional hardening (still local-friendly, not overkill)

### Commit 12 — Disable Kafka topic auto-creation + make topics explicit

**Prompt**

```text
Disable Kafka topic auto-creation.
Add documented explicit topic creation steps (and required Connect internal topics if needed).
Ensure the stack still starts cleanly and the E2E test still works.
```

**Why**

* Reduces accidental topics and typos
* Makes pipeline intentional and reproducible
* Closer to production expectations

---

### Commit 13 — Add resource limits and safety rails

**Prompt**

```text
Add conservative CPU/memory limits in docker-compose for Kafka, Connect, ClickHouse, and ZooKeeper.
Document recommended local Docker resources.
```

**Why**

* Prevents noisy-neighbor issues on laptops
* Avoids ClickHouse or Kafka OOM death spirals
* Makes dev environment stable

---

## End state (after Step II)

* Kafka requires auth for all clients (Connect + Schema Registry included)
* ClickHouse has least-privilege users/roles
* Secrets are mounted locally (not in repo)
* Your original Step I pipeline still works end-to-end
