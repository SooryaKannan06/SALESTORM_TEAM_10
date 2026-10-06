# SALESTORM — STRIDE Security Threat Model

---

## STRIDE Vulnerability Matrix

| STRIDE Category | Specific Flash Sale Threat | Architectural Countermeasure | Risk Level |
| :--- | :--- | :--- | :--- |
| **Spoofing Identity** | Attacker impersonates buyer using stolen token. | RS256 signed JWTs (15m expiry) + Device fingerprinting. | HIGH |
| **Tampering with Data** | Attacker modifies payload to alter quantity=100. | SHA-256 Payload Hash matching + HMAC verification. | CRITICAL |
| **Repudiation** | User claims they never initiated purchase. | Immutable WORM audit logs with Merkle tree signatures. | MEDIUM |
| **Information Disclosure**| PII exposed in logs or network traffic. | TLS 1.3 in-transit, LogSanitizer PII scrubbing. | HIGH |
| **Denial of Service** | Botnet floods API with 500k req/s to drain stock. | Cloudflare WAF + Virtual Waiting Room + Token Bucket. | CRITICAL |
| **Elevation of Privilege**| Normal user invokes admin stock override API. | OAuth2 RBAC scopes enforced at Envoy API Gateway. | HIGH |
