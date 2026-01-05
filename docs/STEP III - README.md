# STEP III — Migrate to a local Kubernetes cluster

Baseline stack: SASL-enabled Kafka (KRaft, 3 controllers + 3 brokers), Schema Registry (JSON Schema validation), ClickHouse (2-node replicated cluster with Keeper + HAProxy), and a documented end-to-end smoke test from Step II.

## Motivation (what this step adds and why)
- Move the full stack onto a local Kubernetes cluster while keeping the same security model (SASL for Kafka, ClickHouse auth).
- Keep changes incremental so each commit is runnable and verifiable.
- Use standard, well-supported tooling for local K8s so the setup is approachable for new users.
- Preserve Docker Compose as a fallback until feature parity is proven.
- Choose patterns that are compatible with a future AWS EKS deployment (Step IV), without introducing AWS-specific setup here.

## Phase 1 — Local Kubernetes foundation (kind + kubectl + helm)

### Commit 1 — Document the local K8s toolchain
**Prompt**
```text
Add a docs/k8s/README.md that explains the local Kubernetes toolchain:
- kind (cluster), kubectl (control), helm (package manager).
- Minimum versions and installation links.
- A short “why this toolchain” section.
- Note: choose versions that are compatible with common EKS defaults.
 - Pin the tool versions in the doc (table of min/recommended).
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
Add a short README in k8s/ describing the layout, naming conventions, and how overlays map to Step IV (EKS).
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
Keep the config portable (no hostPath assumptions that block EKS later).
Use a named cluster (kafka-clickhouse) and a single control-plane node unless explicitly needed.
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
Keep PVCs and StorageClass usage aligned with EKS-compatible patterns.
Avoid hardcoding storageClassName unless required by a chart.
Prefer a standard StorageClass name (e.g., standard) in values files.
```
**Why**
- Kafka and ClickHouse require persistent storage.
- Eliminates “Pending PVC” failures for first-time users.
- Makes cleanup/reset predictable.
 - Avoids rework when moving to EKS.

### Commit 5 — Ingress or port-forward strategy (recommended: Ingress for HTTP)
**Prompt**
```text
Choose and document a local access strategy:
- Recommended: install NGINX ingress controller with hostnames for HTTP access.
- Use kubectl port-forward for ClickHouse native TCP (9000) when needed.
Implement the chosen path and document it.
Define hostnames in a local hosts file example (no DNS automation yet).
Use the official ingress-nginx Helm chart and pin the version.
```
**Why**
- Provides a consistent way to reach services from the host.
- Reduces confusion about service URLs in examples.
- Keeps local dev simple without production-grade ingress.
**Note**
- In K8s, rely on Services + Ingress instead of HAProxy unless you have a specific HAProxy-only requirement.
- Use ingress/Service patterns that map cleanly to EKS (no local-only assumptions baked into manifests).

### Commit 6 — Namespace and common config
**Prompt**
```text
Create a dedicated namespace (kafka-clickhouse) and add common labels/annotations.
Add ConfigMaps/Secrets scaffolding for shared values (no secrets in git).
Document how to inject secrets locally (kubectl create secret or sealed-secrets placeholder).
Adopt a consistent secret naming scheme (e.g., kafka-secrets, clickhouse-secrets).
```
**Why**
- Avoids mixing workloads with unrelated local clusters.
- Keeps manifests clean and discoverable.
- Sets up secret hygiene early.

## Phase 3 — Kafka stack on Kubernetes (secured)

### Commit 7 — Deploy Kafka (KRaft) via Helm
**Prompt**
```text
Deploy Kafka using Confluent for Kubernetes (CFK) in KRaft mode.
Match the Compose topology: 3 controllers + 3 brokers, replication factor = 3.
Enable SASL/PLAIN with secrets provided out-of-repo.
Expose a local listener via the chosen access strategy.
If HTTP UIs are added, define Ingress hostnames (kafka.local) and add /etc/hosts examples.
Document a health check and a CLI smoke test using mounted client.properties.
Pin chart/app versions and record them in docs/k8s/README.md.
Recommended path: CFK operator (Helm) + KRaftController/Kafka CRs in k8s/base/confluent/.
```
**Why**
- Helm is the local standard for reproducible deployments.
- KRaft avoids ZooKeeper even in K8s.
- Keeps security parity with Step II.
- Helm charts used locally should be compatible with EKS defaults.

### Commit 8 — Deploy Schema Registry (JSON Schema)
**Prompt**
```text
Deploy Schema Registry connected to Kafka over SASL.
Expose it locally via Ingress and add a basic "list subjects" check.
Define a hostname (schema-registry.local) and add a /etc/hosts example.
Add a JSON Schema registration example for kafka-json-events using a schema file.
Document the subject naming convention and schema file location.
Recommended chart: bitnami/schema-registry with values in k8s/values/schema-registry.yaml.
```
**Why**
- Validates client auth on Kubernetes before data ingestion.
- Matches Step I/II verification flow.
- Keeps debugging scope small.

## Phase 4 — ClickHouse on Kubernetes

### Commit 9 — Deploy ClickHouse with persistence (replicated)
**Prompt**
```text
Deploy ClickHouse using the Altinity ClickHouse Operator (industry standard) or an equivalent chart.
Match Compose: 2-node replicated cluster + Keeper, with persistent volumes.
Expose HTTP via Ingress + Service and native TCP via port-forward when needed.
Define a hostname (clickhouse.local) and add a /etc/hosts example.
Add a smoke test query.
Pin operator/chart versions and record them in docs/k8s/README.md.
Recommended path: Altinity operator + ClickHouseInstallation CR in k8s/base/clickhouse/.
```
**Why**
- Confirms storage and service access are working.
- Keeps the DB isolated from connector issues.
- Mirrors the Compose validation sequence.
**Note**
- Prefer Service + Ingress for HTTP routing; skip HAProxy unless you need its specific features.
- Keep the operator and CRDs aligned with EKS-compatible storage and networking defaults.

### Commit 10 — ClickHouse users/roles in K8s
**Prompt**
```text
Mount ClickHouse user/role configuration via ConfigMap/Secret.
Document admin + reader connection examples.
Note any differences from the Compose config layout.
Keep user XML compatible with both local and future EKS deployments.
```
**Why**
- Maintains least-privilege design from Step II.
- Keeps secrets out of the repo.
- Avoids mismatched auth between Compose and K8s.

## Phase 5 — End-to-end parity + operating manual

### Commit 11 — End-to-end smoke test on K8s
**Prompt**
```text
Document a full end-to-end smoke test on Kubernetes:
- register schema
- produce messages
- verify rows in ClickHouse
Include all necessary kubectl port-forward or ingress steps.
Keep commands idempotent and runnable in a fresh cluster.
Reference the same schema file used in Compose (configs/schema-registry/kafka-json-events.schema.json).
```
**Why**
- Confirms the pipeline works in K8s, not just on Compose.
- Provides a repeatable regression test.
- Lowers the learning curve for new users.

### Commit 12 — Compose vs K8s parity notes
**Prompt**
```text
Add a short comparison table in docs/README.md:
- what works in Compose
- what works in K8s
- known differences and limitations
Call out any intentional deviations (e.g., ingress vs HAProxy).
Keep the table updated when values/ports diverge.
```
**Why**
- Prevents confusion between environments.
- Sets expectations while K8s migration is incomplete.
- Makes troubleshooting faster.

### Commit 13 — Cluster cleanup and reset
**Prompt**
```text
Add scripts and docs to reset the local K8s environment:
- delete namespace and PVCs
- recreate cluster
Document when to use each option.
Include a "data loss" warning for destructive commands.
Provide a one-command "nuke" script plus a safer "soft reset".
```
**Why**
- Ensures a clean slate when debugging stateful issues.
- Matches the “reset volumes” guidance in Compose.
- Keeps onboarding friction low.

## EKS compatibility checklist (no AWS setup yet)
- Use Helm charts that support KRaft, SASL, and multi-broker replication without vendor-specific patches.
- Keep PVCs/storage classes generic (avoid local-only hostPath assumptions).
- Rely on Kubernetes Services + Ingress for HTTP access; avoid bespoke local-only routing.
- Keep secrets out of git and compatible with Secret/ExternalSecret patterns.
- Use namespaces/labels that can map cleanly to EKS RBAC and resource policies later.
