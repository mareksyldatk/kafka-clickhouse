# Secrets scaffolding (no secrets in git)

This directory is reserved for Kubernetes Secret manifests if needed later. Keep
all real secrets out of the repository.

## Recommended naming
- `kafka-secrets`
- `schema-registry-secrets`
- `clickhouse-secrets`

## Local injection (examples)
Create secrets locally from literals (development only):
```bash
kubectl create secret generic kafka-secrets \
  --namespace kafka-clickhouse \
  --from-literal=username=... \
  --from-literal=password=...
```

Create secrets from a file:
```bash
kubectl create secret generic clickhouse-secrets \
  --namespace kafka-clickhouse \
  --from-file=users.xml=./path/to/users.xml
```

## Production placeholder
If we add sealed-secrets or external secrets later, manifests should live here,
but keep the unsealed values out of git.
