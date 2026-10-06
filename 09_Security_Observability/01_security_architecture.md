# SALESTORM — Module 4: Security & Observability Architecture
## Document 01: Security Architecture, STRIDE Threat Model & Data Protection

---

### 1. Security Architecture Overview

During a high-concurrency e-commerce flash sale, security vulnerabilities (such as bot abuse, API script automated scalping, payment fraud, session hijacking, or SQL injection) directly jeopardize business integrity and stock allocation fairness.

SALESTORM implements a **Defense-in-Depth Security Framework** protecting all tiers of the infrastructure:

```
[ Public Web / Mobile Clients ]
               |
               v
+-------------------------------------------------------+
| LAYER 1: Cloudflare WAF & Edge DDoS Mitigation        | -> TLS 1.3, Bot Management, Rate Limiting
+-------------------------------------------------------+
               |
               v
+-------------------------------------------------------+
| LAYER 2: API Gateway Authorization & Token Validation | -> OAuth2 + JWT (RSA256 Signature Verification)
+-------------------------------------------------------+
               |
               v
+-------------------------------------------------------+
| LAYER 3: Internal Microservices Mutual TLS (mTLS)      | -> Service-to-Service Identity (Spiffe/Spire)
+-------------------------------------------------------+
               |
               v
+-------------------------------------------------------+
| LAYER 4: Database Storage & Encryption At-Rest        | -> AES-256 Envelope Encryption, HashiCorp Vault
+-------------------------------------------------------+
```

---

### 2. STRIDE Threat Modeling Analysis

SALESTORM evaluates system vulnerabilities using the Microsoft **STRIDE** threat model framework:

| STRIDE Category | Specific Flash Sale Threat | Vulnerable Component | Architectural Countermeasure | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| **Spoofing Identity** | Attacker impersonates legitimate buyer using stolen session or forged token. | API Gateway / Auth Service | RS256 signed JWTs with short expiry (15m) + Device fingerprinting. | HIGH |
| **Tampering with Data** | Attacker intercepts `POST /reservations` payload to alter `quantity=100`. | Microservice HTTP APIs | SHA-256 Payload Hash matching + HMAC signature verification. | CRITICAL |
| **Repudiation** | User claims they never initiated purchase or payment. | Order / Payment Log | Immutable SQL Audit Ledger with cryptographically chained log signatures. | MEDIUM |
| **Information Disclosure** | Sensitive payment card tokens or PII exposed in logs or network traffic. | Logging / Microservice APIs | TLS 1.3 in-transit, Log Sanitizer filter (PII masking), PCI-DSS tokenization. | HIGH |
| **Denial of Service (DoS)** | Automated botnet floods API with 500k req/sec to drain server resources. | Edge Gateway / Inventory Svc| Cloudflare Rate Limiting + Virtual Waiting Room + Redis Token Bucket. | CRITICAL |
| **Elevation of Privilege** | Normal user attempts admin stock override API endpoint (`POST /admin/stock`). | Role-Based Access Control | OAuth2 Scopes (`read:inventory`, `write:reservation`, `admin:all`) enforced at Gateway. | HIGH |

---

### 3. Authentication & Authorization Architecture (OAuth2 / JWT)

#### JWT Token Standard Claims
```json
{
  "iss": "https://auth.salestorm.io",
  "sub": "usr_9981245",
  "aud": "api.salestorm.io",
  "exp": 1769938900,
  "iat": 1769938000,
  "jti": "jwt_nonce_7781a",
  "roles": ["CUSTOMER"],
  "scope": "reservation:create payment:execute",
  "fingerprint": "a3f89e1b..."
}
```

#### Verification Protocol at API Gateway
1. Envoy Proxy verifies JWT signature using RSA-256 Public Key (fetched via JWKS endpoint, cached in memory).
2. Checks expiration (`exp > now()`).
3. Rejects blacklisted tokens checked against Redis JWT Revocation List (`salestorm:jwt_blacklist:<jti>`).
4. Extracts `sub` (User ID) and injects upstream header: `X-User-ID: usr_9981245`.

---

### 4. Bot Management & Flash Sale Scalping Defense

Automated purchase bots account for up to 40% of flash sale traffic if unmitigated.

1. **Proof-of-Work (PoW) Challenge at Waiting Room**: Clients entering the Virtual Waiting Room must solve a lightweight CPU PoW challenge (Sha-256 nonce puzzle) taking ~300ms of browser execution time, rendering automated script farms economically ineffective.
2. **Device Fingerprinting & IP Velocity Check**: Rejects >3 purchase attempts within 10 seconds originating from the same ASN or IP subnet.

---

### 5. Secrets Management & Data Encryption

- **Encryption In-Transit**: TLS 1.3 enforced on all external endpoints. mTLS (Mutual TLS via Istio / Envoy Proxy) enforced for all inter-microservice pod-to-pod communications.
- **Encryption At-Rest**: Databases (PostgreSQL) and Redis persistent storage encrypted using **AES-256 Envelope Encryption**.
- **Secrets Management**: Database credentials, payment gateway private keys, and JWT RSA signing keys are injected dynamically into pods at boot time using **HashiCorp Vault** with automatic 30-day key rotation.
- **PCI-DSS Compliance**: No raw Credit Card Numbers (PAN) or CVV values enter or touch SALESTORM infrastructure. All payment fields are handled client-side via Stripe / Adyen iframe SDK tokenization, returning an ephemeral Payment Token (`tok_991823`).
