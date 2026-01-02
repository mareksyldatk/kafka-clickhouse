# Security Model (local development)

This repository is a local, single-developer sandbox. The goal is to keep credentials out of the repo while documenting how auth would be wired when needed. 
Production hardening (mTLS, disk encryption, secret management) is out of scope for Step II.

## Scope and threat model
- Assumes a trusted laptop and local Docker network; no multi-tenant or hostile actors.
- No transport encryption is enabled; everything runs over plaintext inside Docker/localhost.
- Secrets must not be committed. Use `secrets/local.env` (untracked) or runtime exports for local defaults only.
- The same env key names are intended to map cleanly to CI secret stores or Kubernetes `Secret`/`envFrom` later.
- mTLS, at-rest encryption, network ACLs, and secret managers are intentionally deferred.

## Kafka (brokers/controllers)
- Current stack is PLAINTEXT with no auth. If you enable auth locally, use SASL/PLAIN only (no TLS) to keep tooling simple.
- Use separate principals when enabling SASL/PLAIN (e.g., one for Schema Registry, one for clients) instead of sharing a single user.
- Listener security must be applied consistently across all brokers/controllers; this stack does not mix secure and insecure listeners.
- Placeholder SASL files live in `templates/secrets/kafka/`; local copies under `secrets/kafka/` are mounted read-only into Kafka and client containers.

## Schema Registry
- Schema Registry talks to Kafka over the internal Docker network. When SASL/PLAIN is enabled on Kafka, configure distinct credentials per service.
- Schema Registry HTTP API is unauthenticated in this sandbox. Add HTTP auth and TLS if you expose it beyond localhost.

## ClickHouse and HAProxy
- ClickHouse users/roles come from mounted configs under `configs/clickhouse/users.d`; the demo credentials live in your local `secrets/local.env`.
- `secrets/clickhouse/` is mounted for optional TLS material (not enabled by default).
- HAProxy fronting ClickHouse is unauthenticated for convenience in local testing.
- No TLS between HAProxy and ClickHouse nodes in this step. If you need it, enable TLS on the backend servers and update HAProxy accordingly.

## Hardening pointers (future work)
- Turn on TLS/mTLS for Kafka, Schema Registry, and ClickHouse once you move beyond local-only use.
- Replace demo credentials with per-service accounts stored outside git (vault/secret manager), and tighten HAProxy exposure.
- Enable encryption at rest and firewall rules when deploying to shared or cloud environments.
