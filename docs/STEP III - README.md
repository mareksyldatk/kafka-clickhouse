# STEP III — Migrate to a local Kubernetes cluster

Baseline stack: SASL-enabled Kafka (KRaft), Schema Registry, Kafka Connect (ClickHouse sink), ClickHouse, and a documented end-to-end smoke test from Step II.

## Motivation (what this step adds and why)
- Move the full stack onto a local Kubernetes cluster while keeping the same security model (SASL for Kafka, ClickHouse auth).
- Keep changes incremental so each commit is runnable and verifiable.
- Use standard, well-supported tooling for local K8s so the setup is approachable for new users.
- Preserve Docker Compose as a fallback until feature parity is proven.

## Phase 1 — Local Kubernetes foundation (kind + kubectl + helm)

### Commit 1 — Document the local K8s toolchain
**Prompt**
```text
Add a docs/k8s/README.md that explains the local Kubernetes toolchain:
- kind (cluster), kubectl (control), helm (package manager).
- Minimum versions and installation links.
- A short “why this toolchain” section.
No cluster changes yet.
```
**Why**
- Establishes a known baseline before manifests are introduced.
- Helps new users avoid mismatched tool versions.
- Makes the migration reproducible across machines.

**Install snippets (macOS/Homebrew)**
```bash
brew install kind kubectl helm
kind version
kubectl version --client
helm version
```

### Commit 2 — K8s directory scaffold
**Prompt**
```text
Add a k8s/ directory scaffold:
- k8s/base/ for shared manifests
- k8s/overlays/local/ for local cluster overrides
- k8s/values/ for Helm values files
Add a short README in k8s/ describing the layout.
No workloads yet.
```
**Why**
- Prevents one-off manifests scattered across the repo.
- Keeps “base vs local” differences explicit.
- Allows staged migration without rewriting existing Compose files.

### Commit 3 — kind cluster config + helper scripts
**Prompt**
```text
Add a kind cluster config with deterministic ports for local access.
Add scripts to:
- create the cluster
- delete the cluster
- load local images if needed
Document usage in docs/k8s/README.md.
```
**Why**
- Guarantees stable local endpoints for smoke tests.
- Makes cluster lifecycle a one-command operation.
- Avoids manual setup drift between developers.

## Phase 2 — Cluster essentials (storage, ingress, namespaces)

### Commit 4 — Storage class + PVC defaults
**Prompt**
```text
Add manifests to ensure a default StorageClass is available in the local cluster.
Document how volumes map to the host and how to reset them.
```
**Why**
- Kafka and ClickHouse require persistent storage.
- Eliminates “Pending PVC” failures for first-time users.
- Makes cleanup/reset predictable.

### Commit 5 — Ingress or port-forward strategy
**Prompt**
```text
Choose and document a local access strategy:
- Option A: install NGINX ingress controller with hostnames.
- Option B: standardize on kubectl port-forward commands.
Implement the chosen path and document it.
```
**Why**
- Provides a consistent way to reach services from the host.
- Reduces confusion about service URLs in examples.
- Keeps local dev simple without production-grade ingress.

### Commit 6 — Namespace and common config
**Prompt**
```text
Create a dedicated namespace (kafka-clickhouse) and add common labels/annotations.
Add ConfigMaps/Secrets scaffolding for shared values (no secrets in git).
```
**Why**
- Avoids mixing workloads with unrelated local clusters.
- Keeps manifests clean and discoverable.
- Sets up secret hygiene early.

## Phase 3 — Kafka stack on Kubernetes (secured)

### Commit 7 — Deploy Kafka (KRaft) via Helm
**Prompt**
```text
Deploy Kafka using a Helm chart (Bitnami or equivalent) in KRaft mode.
Enable SASL/PLAIN with secrets provided out-of-repo.
Expose a local listener via the chosen access strategy.
Document a health check and a CLI smoke test.
```
**Why**
- Helm is the local standard for reproducible deployments.
- KRaft avoids ZooKeeper even in K8s.
- Keeps security parity with Step II.

### Commit 8 — Deploy Schema Registry
**Prompt**
```text
Deploy Schema Registry connected to Kafka over SASL.
Expose it locally and add a basic "list subjects" check.
```
**Why**
- Validates client auth on Kubernetes before adding Connect.
- Matches Step I/II verification flow.
- Keeps debugging scope small.

### Commit 9 — Deploy Kafka Connect + ClickHouse sink
**Prompt**
```text
Deploy Kafka Connect configured for SASL.
Install the ClickHouse sink plugin via a custom image or init container.
Document how to register the connector via the Connect REST API.
```
**Why**
- Connect is the critical integration point.
- Plugin installation must be reproducible.
- REST-based deployment keeps workflows consistent.

## Phase 4 — ClickHouse on Kubernetes

### Commit 10 — Deploy ClickHouse with persistence
**Prompt**
```text
Deploy ClickHouse with a persistent volume claim.
Expose HTTP and native ports via the chosen access method.
Add a smoke test query.
```
**Why**
- Confirms storage and service access are working.
- Keeps the DB isolated from connector issues.
- Mirrors the Compose validation sequence.

### Commit 11 — ClickHouse users/roles in K8s
**Prompt**
```text
Mount ClickHouse user/role configuration via ConfigMap/Secret.
Wire Kafka Connect to the writer user.
Document read-only connection examples.
```
**Why**
- Maintains least-privilege design from Step II.
- Keeps secrets out of the repo.
- Avoids mismatched auth between Compose and K8s.

## Phase 5 — End-to-end parity + operating manual

### Commit 12 — End-to-end smoke test on K8s
**Prompt**
```text
Document a full end-to-end smoke test on Kubernetes:
- register schema
- produce messages
- verify rows in ClickHouse
Include all necessary kubectl port-forward or ingress steps.
```
**Why**
- Confirms the pipeline works in K8s, not just on Compose.
- Provides a repeatable regression test.
- Lowers the learning curve for new users.

### Commit 13 — Compose vs K8s parity notes
**Prompt**
```text
Add a short comparison table in docs/README.md:
- what works in Compose
- what works in K8s
- known differences and limitations
```
**Why**
- Prevents confusion between environments.
- Sets expectations while K8s migration is incomplete.
- Makes troubleshooting faster.

### Commit 14 — Cluster cleanup and reset
**Prompt**
```text
Add scripts and docs to reset the local K8s environment:
- delete namespace and PVCs
- recreate cluster
Document when to use each option.
```
**Why**
- Ensures a clean slate when debugging stateful issues.
- Matches the “reset volumes” guidance in Compose.
- Keeps onboarding friction low.
