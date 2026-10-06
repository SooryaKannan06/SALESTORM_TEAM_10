# Architecture Decision Record (ADR)
## ADR-004: Resilience Strategy — Idempotent Retries, Timeout Budgets, and Circuit Breakers

---

### Status
**ACCEPTED**

### Context
Transient network glitches and external API slowdowns (such as payment gateways) must not cause cascading thread starvation across SALESTORM microservices.

---

### Decision
1. **Strict Timeout Budgets**: Illustrative starting limits enforced across service calls (Gateway: 2500ms, Inventory: 800ms, Payment: 2000ms).
2. **Idempotent Retries Only**: Retries are permitted ONLY for transient errors on idempotent operations using Full Jitter Exponential Backoff ($t_{\text{sleep}} = \text{random}(0, \min(t_{\text{max}}, t_{\text{base}} \times 2^n))$). Retrying non-idempotent operations is strictly forbidden.
3. **Circuit Breaker Placement**: Circuit breakers (Resilience4j / Envoy) are deployed for unstable external dependencies (Payment Gateways, Shipping APIs).
4. **Scope Limitation**: Circuit breakers manage external service availability; they do NOT solve database consistency.

---

### Trade-offs & Consequences
- Protects application threads from blocking on slow external dependencies.
- Prevents thundering herd retry storms against struggling third-party APIs.
