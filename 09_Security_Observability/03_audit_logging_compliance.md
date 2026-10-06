# SALESTORM — Module 4: Security & Observability Architecture
## Document 03: Security Audit Logging, PII Sanitization & Compliance

---

### 1. Audit Logging Architecture & Regulatory Need

In e-commerce platforms handling high-value flash sales, maintaining an tamper-proof, append-only security audit log is mandatory for regulatory compliance (PCI-DSS v4.0, GDPR Article 32, SOC 2 Type II) and post-incident forensic investigations.

```
[ Microservice App Threads ]
             |
             v
[ LogSanitizer Filter ] ----> Masks PII (Emails, Card Tokens, Auth Headers)
             |
             v
[ Structured JSON Logger (Logback/Zap) ]
             |
             v
[ Vector / FluentBit Collector ]
             |
       +-----+--------------------+
       |                          |
       v                          v
[ Grafana Loki ]         [ AWS S3 Object Lock ]
(Real-Time Search)       (WORM Append-Only Immutable Storage)
```

---

### 2. Structured JSON Security Audit Schema

Every state-changing operation generates a standardized, structured JSON audit log entry:

```json
{
  "timestamp": "2026-10-05T10:30:00.124Z",
  "audit_id": "aud_99812-a8b2",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "event_type": "INVENTORY_RESERVATION_CREATED",
  "actor": {
    "user_id": "usr_9981245",
    "ip_address": "198.51.100.42",
    "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X)",
    "client_id": "mobile_ios_app"
  },
  "resource": {
    "type": "PRODUCT_INVENTORY",
    "id": "prod_1001",
    "reservation_id": "res_99812"
  },
  "action_details": {
    "quantity_reserved": 1,
    "previous_stock_level": 100,
    "new_stock_level": 99,
    "idempotency_key": "idem_req_7781a",
    "ttl_seconds": 600
  },
  "security_context": {
    "auth_method": "OAUTH2_JWT",
    "token_jti": "jwt_nonce_7781a",
    "tls_version": "TLSv1.3"
  },
  "status": "SUCCESS"
}
```

---

### 3. Log Sanitization & PII Masking Engine

To prevent accidental exposure of Personally Identifiable Information (PII) or sensitive credit card metadata in log aggregators:

```java
public class PiiLogSanitizer {

    private static final Pattern CREDIT_CARD_PATTERN = Pattern.compile("\\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14})\\b");
    private static final Pattern EMAIL_PATTERN = Pattern.compile("(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b");
    private static final Pattern AUTH_HEADER_PATTERN = Pattern.compile("(?i)(Bearer\\s+)[A-Za-z0-9-_=]+\\.[A-Za-z0-9-_=]+\\.[A-Za-z0-9-_=]+");

    public static String sanitize(String rawLog) {
        if (rawLog == null) return null;
        
        String masked = CREDIT_CARD_PATTERN.matcher(rawLog).replaceAll("****-****-****-****");
        masked = EMAIL_PATTERN.matcher(masked).replaceAll("u***@domain.com");
        masked = AUTH_HEADER_PATTERN.matcher(masked).replaceAll("$1[REDACTED_JWT_TOKEN]");
        
        return masked;
    }
}
```

---

### 4. Immutable Log Storage & Write-Once-Read-Many (WORM) Compliance

1. **Storage Tiering**:
   - Hot Logs (0-7 Days): Ingested into Grafana Loki for instant debugging and search.
   - Cold Audit Logs (8 Days - 7 Years): Exported hourly to **AWS S3 Glacier Vault** configured with **Compliance Mode Object Lock**.
2. **Immutability Guarantee**: Once written to S3 Glacier Vault in Compliance Mode, no user (including root AWS accounts) can overwrite or delete audit logs until the 7-year retention period expires.
3. **Cryptographic Log Tamper Detection**: Every hourly batch of audit logs generates a SHA-256 Merkle Tree root hash stored in a separate immutable ledger.
