# Kubernetes manifests layout

This directory is a scaffold for future Kubernetes manifests. No workloads are defined yet.

## Layout
- `k8s/base/` — shared manifests and common defaults.
- `k8s/overlays/local/` — local cluster overrides (kind).
- `k8s/values/` — Helm values files, grouped by chart or environment.

## Naming conventions
- Keep one workload per file and name files after the resource (`kafka-broker.yaml`, `schema-registry.yaml`).
- Use lowercase kebab-case for filenames and directories.
- Values files should follow `<chart>-<env>.yaml` (example: `clickhouse-local.yaml`).

## Overlay strategy (Step IV / EKS)
- `k8s/base/` stays environment-agnostic.
- `k8s/overlays/local/` is for kind-only differences (ports, node selectors, low resources).
- A future `k8s/overlays/eks/` will layer on AWS-specific settings without changing `base/`.
