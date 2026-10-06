# SALESTORM — Dynamic Secrets Management (HashiCorp Vault)

---

## 1. Zero Hardcoded Credentials Policy

No database passwords, API tokens, JWT private signing keys, or TLS certificates are committed to codebase repositories or static config files.

---

## 2. Dynamic Secret Injection
- Microservices use Vault Agent sidecars to retrieve short-lived database credentials dynamically at pod startup.
- Database passwords rotate automatically every 30 days.
- Secrets stored in memory only; never dumped to disk or environment variables.
