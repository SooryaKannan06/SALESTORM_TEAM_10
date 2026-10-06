# Architecture Decision Record (ADR)
## ADR-008: Security Architecture, OAuth2/JWT Authentication, and PCI-DSS Tokenization

---

### Status
**ACCEPTED**

### Context
Flash sales are prime targets for automated scalping bots, payment fraud, account takeover, and DDoS attacks. Security controls must be embedded without introducing high latency.

---

### Decision
1. **Edge-to-Service Security**: OAuth2 + RS256 signed JWT validation at API Gateway. Inter-microservice communication encrypted via mTLS.
2. **PCI-DSS Compliance**: Raw payment card numbers (PAN/CVV) NEVER enter SALESTORM servers. Payment SDK tokenization handles cards client-side and returns tokenized references.
3. **Secrets Management**: Credentials and keys injected dynamically via HashiCorp Vault.
4. **Log Sanitization**: PII log scrubber filters credit card tokens, emails, and bearer tokens before log ingestion.

---

### Trade-offs & Consequences
- Ensures regulatory compliance (PCI-DSS v4.0, GDPR).
- Eliminates risk of sensitive payment data leakage in application logs.
