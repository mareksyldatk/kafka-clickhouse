# STEP II — Add auth and secrets safely (on top of the current stack)

Baseline stack: KRaft Kafka (3 controllers/3 brokers) with Schema Registry, Kafka Connect (native ClickHouse sink baked in), a 2-node ClickHouse cluster behind HAProxy, and health-based startup.

## Motivation (what this step adds and why)
- Add authentication across Kafka and ClickHouse so local pipelines aren’t “open by default”.
- Keep it incremental and reversible: enable auth one surface at a time, validate, then proceed.
- Keep secrets out of the repo/.env to match better practices (and avoid accidental commits).
- Enforce the least privilege for service and human access, with quick negative tests to prove it.

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
- Sets expectations for “secure enough for local” before changing configs.
- Keeps scope small (no TLS/mTLS yet) so work stays manageable.
- Avoids rework by agreeing on the plan up front.

### Commit 2 — Add Kafka JAAS/client config files (mounted, placeholders)
**Prompt**
```text
Create Kafka SASL/PLAIN config files under configs/kafka/ (broker + client JAAS, client.properties).
Use placeholders only; real secrets come from env/secret files (documented).
Mount them in compose, but do not enable SASL yet.
```
**Why**
- Lets us validate mounts and paths without risking a broken broker.
- Keeps passwords out of git and .env by design.
- Establishes a clear place for client/server auth configs.

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
- Changes only the broker side so failures are easy to isolate.
- Keeps ports/layout stable to avoid client churn.
- Gives a known-good secured broker baseline.

### Commit 4 — Update Schema Registry to auth to Kafka
**Prompt**
```text
Configure Schema Registry to use SASL/PLAIN to Kafka (mounted client config or env vars).
Add a README smoke test (list subjects) proving Registry works under SASL.
```
**Why**
- Proves a simple client path works with SASL before touching Connect.
- Limits blast radius to one service.
- Keeps connector troubleshooting separate from auth rollout.

### Commit 5 — Update Kafka Connect worker to auth to Kafka
**Prompt**
```text
Configure Connect worker to use SASL/PLAIN to Kafka.
Ensure internal topics remain usable.
Adjust (or add new) README smoke test for Connect REST + internal topics under SASL.
Same with smoke_test.sh.
Do not redeploy sink connector yet.
```
**Why**
- Connect is the main consumer/producer; it must survive auth changes.
- Verifies internal topics (configs/offsets/status) still work.
- Avoids chasing connector issues while fixing client auth.

### Commit 6 — Re-validate Kafka → Connect → ClickHouse under SASL
**Prompt**
```text
Update the ClickHouse sink connector config (if needed) so it works with SASL-enabled Kafka.
Run/refresh the Avro end-to-end smoke test and document the steps.
No new features; just security compatibility of all examples/smoke tests/scripts.
```
**Why**
- Ensures the core pipeline still runs after broker/client auth.
- Avoids “secure but stalled” ingestion.
- Locks in a tested secure baseline before moving on.

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
- Validates the config mounts and syntax without blocking access yet.
- Sets least-privilege roles before enforcement so grants can be tested.
- Avoids breaking ingestion while roles/grants are being designed.

### Commit 8 — Enforce ClickHouse authentication
**Prompt**
```text
Enable ClickHouse auth using the mounted users/roles:
- disable stock default user
- wire Kafka Connect to the writer user
- document readonly vs writer connection examples
```
**Why**
- Creates a clear boundary: unauthenticated access fails.
- Confirms writer/readonly roles actually work for apps and humans.
- Surfaces grant gaps before production-like use.

### Commit 9 — Negative tests for least privilege
**Prompt**
```text
Add README checks showing:
- readonly can SELECT but cannot INSERT/CREATE
- writer can INSERT into target tables but cannot DROP/ALTER outside scope
No code changes beyond necessary grants/docs.
```
**Why**
- Shows least-privilege is real by testing what should fail.
- Prevents role creep (e.g., writer accidentally being admin).
- Keeps grants disciplined as schemas evolve.

## Phase 3 — Secrets hygiene (local-only)

### Commit 10 — Move secrets out of .env into mounted files
**Prompt**
```text
Remove passwords from .env; keep only non-sensitive defaults.
Add an ignored secrets/ path with sample templates; mount into Kafka/Schema Registry/Connect/ClickHouse.
Document how to create secrets locally and ensure .gitignore covers them.
```
**Why**
- Reduces risk of committing credentials by mistake.
- Matches how secrets will be handled later (K8s/CI), improving portability.
- Keeps setup reproducible without exposing sensitive values.
