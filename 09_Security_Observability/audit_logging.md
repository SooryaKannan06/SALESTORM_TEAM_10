# SALESTORM — Audit Logging & PII Sanitization

---

## 1. Structured JSON Audit Schema

Every state-changing inventory, payment, or order operation emits a structured audit log entry:

```json
{
  "timestamp": "2026-10-05T10:30:00.124Z",
  "audit_id": "aud_99812-a8b2",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "event_type": "INVENTORY_RESERVATION_CREATED",
  "user_id": "usr_9981245",
  "resource_id": "prod_1001",
  "action": "RESERVE",
  "status": "SUCCESS"
}
```

---

## 2. PII Masking & LogSanitizer Filter

RegEx interceptor strips sensitive values before logging:
- Credit Card Numbers $\rightarrow$ `****-****-****-****`
- Emails $\rightarrow$ `u***@domain.com`
- Bearer Tokens $\rightarrow$ `[REDACTED_JWT]`

---

## 3. WORM Immutable Storage

Audit logs are archived to **AWS S3 Glacier Vault** in **Compliance Mode (WORM)** with a strict 7-year retention period to ensure legal tamper-resistance.
