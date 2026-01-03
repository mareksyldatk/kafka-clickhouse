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
