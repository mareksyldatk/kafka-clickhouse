# Local Kubernetes Toolchain

This repo uses a simple, industry-standard local Kubernetes toolchain for Phase I:
- kind: runs a local multi-node Kubernetes cluster using Docker nodes.
- kubectl: the standard CLI to control and inspect the cluster.
- helm: package manager for Kubernetes charts.

## Why this toolchain
- It mirrors common production workflows (kubectl + Helm) while keeping local setup lightweight.
- kind is designed for local clusters and CI, and supports multi-node clusters that approximate managed control planes.
- Helm is the de facto standard for installing and managing Kubernetes packages.

## Kind cluster config (local)
- Cluster name: `kafka-clickhouse`
- Config: `k8s/kind/cluster.yaml`
- One control-plane node (no workers) until workloads require more nodes.
- Deterministic local ports:
  - Kubernetes API server: `127.0.0.1:6443`
  - NodePort mappings: `30080` (HTTP), `30443` (HTTPS)

The config stays portable by avoiding hostPath mounts; local differences should live in `k8s/overlays/local/`.

## Version pins (EKS-compatible)
These version pins align with Amazon EKS standard support versions (1.32-1.34) and Kubernetes version-skew guidance. Keep kubectl within one minor version of your cluster.

| Tool | Minimum | Recommended | Notes |
| --- | --- | --- | --- |
| kind | v0.30.0 | v0.31.0 | Use a kindest/node image that matches the target Kubernetes minor version. |
| kubectl | v1.32.x | v1.34.x | EKS standard support currently includes 1.32-1.34; kubectl is supported within +/-1 minor version of the API server. |
| helm | v3.19.2 | v4.0.1 | Helm v4.0.1 is the current major release; Helm v3.19.2 is the latest v3 patch. |

## Installation links
- kind: https://kind.sigs.k8s.io/docs/user/quick-start/
- kubectl: https://kubernetes.io/docs/tasks/tools/
- helm: https://helm.sh/docs/intro/install/

## Local workflow scripts
Install local Kubernetes toolchain (macOS/Homebrew):
```bash
scripts/k8s/setup_k8s_toolchain_macos.sh
```

Create the local cluster:
```bash
scripts/k8s/create_kind_cluster.sh
```

Delete the local cluster:
```bash
scripts/k8s/delete_kind_cluster.sh
```

Load local images into the cluster:
```bash
scripts/k8s/load_kind_image.sh <image> [image...]
```

## Kafka (Confluent for Kubernetes)
We deploy Kafka using Confluent for Kubernetes (CFK) with KRaft. This mirrors the CFK quickstart but only includes KRaftController + Kafka.

Install the operator (Helm):
```bash
scripts/k8s/install_cfk_operator.sh
```

Ensure the local namespace + StorageClass are applied:
```bash
kubectl apply -k k8s/overlays/local
```

Make sure secrets are loaded first:
```bash
scripts/k8s/load_secrets.sh --all
```

Apply the Kafka + KRaftController manifests:
```bash
scripts/k8s/apply_cfk_kafka.sh
```

Manifests:
```
k8s/base/confluent/
```

SASL/PLAIN credentials come from the `kafka-plain-users` secret created by:
```bash
scripts/k8s/load_secrets.sh --all
```

Version pins:
- Operator chart: `confluentinc/confluent-for-kubernetes` `0.1351.59`
- Operator app: `3.1.1`
- Confluent Platform (Kafka): `8.1.1`

Local listener (NodePort, broker external access):
- `kafka.local:30090` (bootstrap)
- `kafka.local:30091` (broker 0)
- `kafka.local:30092` (broker 1)
- `kafka.local:30093` (broker 2)

Add to `/etc/hosts`:
```
127.0.0.1  kafka.local
```

NodePort offsets must stay within the 30000–32767 range; `30090` keeps all broker ports in range.

### Kafka health check
```bash
kubectl get kafka -n kafka-clickhouse
kubectl get pods -n kafka-clickhouse
```

### Kafka CLI smoke test (client.properties)
The Kafka client config is mounted into the `kafka-client` helper pod at:
```
/mnt/secrets/kafka-client-config/client.properties
```
The `kafka-client` deployment is for local CLI tests only.
Reminder: update `secrets/local.env` with real values before running the smoke test.

List topics:
```bash
kubectl exec -n kafka-clickhouse deploy/kafka-client -- \
  kafka-topics \
  --bootstrap-server kafka:9092 \
  --command-config /mnt/secrets/kafka-client-config/client.properties \
  --list
```

Host-side smoke test (Docker client + NodePort):
```bash
docker run --rm \
  --add-host kafka.local:host-gateway \
  -v "$(pwd)/secrets/kafka/client.properties:/etc/kafka/client.properties:ro" \
  confluentinc/cp-kafka:8.1.1 \
  kafka-topics \
  --bootstrap-server kafka.local:30090 \
  --command-config /etc/kafka/client.properties \
  --list
```

## Local access strategy (Ingress + port-forward)
### Ingress (HTTP)
We use the official `ingress-nginx` Helm chart with a pinned version and NodePort mapping for predictable local access. The chart is pinned to `4.14.1`. 

Install the ingress controller:
```bash
scripts/k8s/install_ingress_nginx.sh
```

Smoke test (after install):
```bash
scripts/tests/k8s_smoke_test.sh
```

Values file:
```
k8s/values/ingress-nginx-local.yaml
```

Local hostnames (example):
```
127.0.0.1  kafka.local schema-registry.local clickhouse.local
```
Add entries like the above to `/etc/hosts` for any Ingress hostnames you define. No DNS automation is used.

NodePort mappings must be in the standard 30000–32767 range; the local values file pins HTTP/HTTPS to `30080`/`30443`.

### Port-forward (native TCP)
Use port-forward when you need a native TCP port (e.g., ClickHouse 9000):
```bash
kubectl port-forward svc/<service> 9000:9000 -n <namespace>
```

## StorageClass + local volumes
Apply the local StorageClass and provisioner:
```bash
kubectl apply -k k8s/overlays/local
```

This installs a default `standard` StorageClass backed by the local-path provisioner (kind only). PVCs can omit `storageClassName` unless a chart requires it. Prefer `standard` in values files when a name is needed.

### How it fits together (local storage)
```
Namespace: <app-namespace>                      Namespace: local-path-storage
---------------------------                     ---------------------------
Pod (app)                                       Pod (local-path-provisioner)
   |                                                     |
   | uses PVC                                            | watches PVCs
   v                                                     v
PVC --------------------------> StorageClass: standard -> PV created
                                                         |
                                                         |
                                                         v
                                                 kind node storage
                                             /var/local/path-provisioner
```

The provisioner runs in `local-path-storage`, watches for PVCs across the cluster, creates PVs on demand, and stores data inside the kind node container. Deleting the PVC deletes the PV data (reclaim policy: Delete).

### Where data lives (kind)
Persistent volumes are stored inside the kind node container at:
```
/var/local/path-provisioner
```
On macOS, this path lives inside the Docker VM, not directly on the host filesystem.

### Resetting local volumes
- Delete the cluster (removes all local PV data):
```bash
scripts/k8s/delete_kind_cluster.sh
```
- Or delete the local-path storage namespace (recreates on next apply):
```bash
kubectl delete namespace local-path-storage
kubectl apply -k k8s/overlays/local
```

## Namespace + shared config
Apply the namespace and shared ConfigMaps:
```bash
kubectl apply -k k8s/overlays/local
```

This creates the `kafka-clickhouse` namespace with common labels/annotations and scaffolds shared ConfigMaps:
- `kafka-shared`
- `schema-registry-shared`
- `clickhouse-shared`

## Secrets (local injection)
Secrets are created locally and are never committed to git. Use a consistent naming scheme:
- `kafka-plain-users`
- `kafka-client-config`
- `clickhouse-secrets`

After updating `secrets/local.env`, re-run `scripts/setup/initial_setup.sh` to render the Kafka secret files under `secrets/kafka/`.

Create Kafka SASL secrets from files:
```bash
kubectl create secret generic kafka-plain-users \
  --namespace kafka-clickhouse \
  --from-file=plain-users.json=secrets/kafka/plain-users.json \
  --from-file=plain-interbroker.txt=secrets/kafka/plain-interbroker.txt
```

Create a secret from a file:
```bash
kubectl create secret generic clickhouse-secrets \
  --namespace kafka-clickhouse \
  --from-file=users.xml=./path/to/users.xml
```

Or use the helper script (idempotent apply):
```bash
scripts/k8s/load_secrets.sh --all
```

Kafka SASL files (used by CFK):
- `secrets/kafka/plain-users.json`
- `secrets/kafka/plain-interbroker.txt`
- `secrets/kafka/client.properties`
`plain-users.json` is a JSON map of `username: password` pairs.
`plain-interbroker.txt` provides the inter-broker username/password used by Kafka.

Template file:
```
templates/secrets/clickhouse/users.xml
```

Sealed-secrets or external secrets can be added later; keep unsealed values out of git.

## `kubectl` quick lookup

### Cluster + context
- `kubectl config get-contexts` — list contexts
- `kubectl config use-context kind-kafka-clickhouse` — switch context
- `kubectl cluster-info` — cluster endpoints

### Nodes + namespaces
- `kubectl get nodes -o wide` — node status + IPs
- `kubectl get namespaces` — list namespaces
- `kubectl create namespace <name>` — add namespace

### Workloads + resources
- `kubectl get pods -A` — all pods
- `kubectl get deploy -A` — all deployments
- `kubectl get svc -A` — all services
- `kubectl describe pod <pod> -n <ns>` — pod details/events

### Logs + exec
- `kubectl logs <pod> -n <ns> --tail=200` — recent logs
- `kubectl logs -f <pod> -n <ns>` — follow logs
- `kubectl exec -it <pod> -n <ns> -- /bin/sh` — shell in container

### Apply + cleanup
- `kubectl apply -k k8s/overlays/local` — apply local kustomize
- `kubectl delete -k k8s/overlays/local` — delete local kustomize
- `kubectl delete pod <pod> -n <ns>` — restart a pod

### Troubleshooting
- `kubectl get events -A --sort-by=.metadata.creationTimestamp` — recent events
- `kubectl top pods -A` — pod CPU/mem (metrics-server required)

### Secrets (safe inspection)
- `kubectl get secrets -n kafka-clickhouse` — list secrets in namespace
- `kubectl describe secret kafka-plain-users -n kafka-clickhouse` — metadata only
- `kubectl get secret clickhouse-secrets -n kafka-clickhouse -o yaml` — full secret (base64 data)
- `kubectl get secret clickhouse-secrets -n kafka-clickhouse -o jsonpath='{.data.users\\.xml}' | base64 -d` — decode one key
