# STEP II — Add auth and secrets safely (on top of the current stack)

Baseline stack: KRaft Kafka (3 controllers/3 brokers) with Schema Registry, Kafka Connect (native ClickHouse sink baked in), a 2-node ClickHouse cluster behind HAProxy, and health-based startup.

## Phase 1 — Kafka SASL/PLAIN (no TLS in local)

### Commit 1 — Document the local security model
**Prompt**
```text
Add a SECURITY.md (or README section) that defines the local model:
- Kafka: SASL/PLAIN only (no TLS), separate principals for Schema Registry and Kafka Connect.
- ClickHouse: users/roles via mounted config; HAProxy stays unauthenticated for local.
- Threat model: local dev only; mTLS and at-rest encryption are out of scope for Step II.
No compose changes yet.
```
**Why**
- Aligns contributors on what “secure enough for local” means.
- Prevents over-scoping (keeps TLS/mTLS out for now).
- Reduces churn when we start touching config.

### Commit 2 — Add Kafka JAAS/client config files (mounted, placeholders)
**Prompt**
```text
Create Kafka SASL/PLAIN config files under configs/kafka/ (broker + client JAAS, client.properties).
Use placeholders only; real secrets come from env/secret files (documented).
Mount them in compose, but do not enable SASL yet.
```
**Why**
- Separates “files mount correctly” from “auth is enabled”.
- Keeps passwords out of the repo and .env.
- Sets up repeatable paths for brokers and clients.

### Commit 3 — Enable SASL/PLAIN on Kafka internal listener
**Prompt**
```text
Turn on SASL_PLAINTEXT for the internal listener in docker-compose.
Point brokers to the mounted JAAS file.
Keep listener layout/ports stable.
Add a README check to confirm brokers start healthy under SASL.
Do not update any clients yet.
```
**Why**
- Single variable: broker security only.
- Confines risk to broker startup.
- Establishes the secured baseline before touching clients.

### Commit 4 — Update Schema Registry to auth to Kafka
**Prompt**
```text
Configure Schema Registry to use SASL/PLAIN to Kafka (mounted client config or env vars).
Add a README smoke test (list subjects) proving Registry works under SASL.
```
**Why**
- Validates the first Kafka client path under auth.
- Keeps scope narrow (one service).
- Avoids mixing client fixes with connector changes.

### Commit 5 — Update Kafka Connect worker to auth to Kafka
**Prompt**
```text
Configure Connect worker to use SASL/PLAIN to Kafka.
Ensure internal topics remain usable.
Add a README smoke test for Connect REST + internal topics under SASL.
Do not redeploy sink connector yet.
```
**Why**
- Connect is the main client; offsets/config/status must survive auth.
- Catches client auth issues before touching connectors.
- Keeps end-to-end debugging clean.

### Commit 6 — Re-validate Kafka → Connect → ClickHouse under SASL
**Prompt**
```text
Update the ClickHouse sink connector config (if needed) so it works with SASL-enabled Kafka.
Run/refresh the Avro end-to-end smoke test and document the steps.
No new features; just security compatibility.
```
**Why**
- Confirms the core data path still works after securing Kafka.
- Prevents “auth on, ingestion off” surprises.
- Locks in a known-good end-to-end flow.

## Phase 2 — ClickHouse auth + least privilege

### Commit 7 — Add ClickHouse users/roles (mounted)
**Prompt**
```text
Add ClickHouse user/role config under configs/clickhouse/:
- writer for Kafka Connect (minimal grants on target DB/tables)
- readonly for humans
Keep default access open for now (no enforcement yet).
Document credentials sourcing (env/secret files), not hardcoded values.
```
**Why**
- Proves config mounting/syntax first.
- Sets least-privilege roles before enforcing auth.
- Avoids breaking ingestion while designing grants.

### Commit 8 — Enforce ClickHouse authentication
**Prompt**
```text
Enable ClickHouse auth using the mounted users/roles:
- disable stock default user
- wire Kafka Connect to the writer user
- document readonly vs writer connection examples
```
**Why**
- Hard boundary: unauthenticated access stops.
- Validates least-privilege works for both automation and humans.
- Surfaces grant mistakes early.

### Commit 9 — Negative tests for least privilege
**Prompt**
```text
Add README checks showing:
- readonly can SELECT but cannot INSERT/CREATE
- writer can INSERT into target tables but cannot DROP/ALTER outside scope
No code changes beyond necessary grants/docs.
```
**Why**
- Security needs negative tests.
- Prevents “writer is admin by accident”.
- Keeps privileges tight as schemas evolve.

## Phase 3 — Secrets hygiene (local-only)

### Commit 10 — Move secrets out of .env into mounted files
**Prompt**
```text
Remove passwords from .env; keep only non-sensitive defaults.
Add an ignored secrets/ path with sample templates; mount into Kafka/Schema Registry/Connect/ClickHouse.
Document how to create secrets locally and ensure .gitignore covers them.
```
**Why**
- Reduces risk of committing credentials.
- Aligns local dev with how secrets will be handled later (K8s/CI).
- Keeps setup reproducible without exposing secrets.
