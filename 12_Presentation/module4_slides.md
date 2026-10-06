# SALESTORM — Module 4 Presentation Slides
## Concurrency, Reliability, Security & Observability

---

### Slide 1: MODULE 4 — RELIABILITY ENGINEERING
- **System**: SALESTORM — High-Scale Flash Sale Platform
- **Presenter**: Team Member 4 (Reliability & System Design Engineer)
- **Scope**: Concurrency Controls, Inventory Protection, Failure Recovery, Security & Observability

---

### Slide 2: 10,000 Users vs 100 Units
- **The Challenge**: 10,000 concurrent customers click "Buy Now" for 100 stock units.
- **Invariants**:
  - `successful_reservations <= available_inventory` (Max 100)
  - `successful_orders <= successfully_confirmed_reservations` (Max 100)
  - `inventory_quantity >= 0` (Zero oversell)
- **Key Realization**: At most 100 reservations can succeed. Actual successful orders may be lower if payments fail or reservations expire.

---

### Slide 3: Concurrency Strategy
- **Layer 1: Admission Control & VWR**: Shapes incoming peak traffic at edge gateway.
- **Layer 2: Idempotency Interceptor**: Redis fast lock + PostgreSQL `UNIQUE(idempotency_key)` catches 2% duplicate flood in <1.5ms.
- **Layer 3: Atomic Redis Fast-Path**: Executes single-threaded Lua script on `{product_1001}` hash slot. Rejects 9,900 losing requests instantly in-memory.
- **Layer 4: PostgreSQL Durable Source of Truth**: Stores durable reservation and audit records.

---

### Slide 4: Reservation Lifecycle
```
AVAILABLE ---> RESERVED ---> PAYMENT_PENDING ---> CONFIRMED ---> SOLD
                  |                |
                  | (Timeout)      | (Declined)
                  v                v
               RELEASED         RELEASED
```
- **Automated 10-Minute TTL**: Redis TTL + periodic SQL sweeper.
- **Idempotent Release**: Inventory restored once.
- **Expiry vs Payment Race Rule**: Only a valid unexpired reservation can transition to `CONFIRMED`.

---

### Slide 5: Failure Recovery Protocols
- **30-Second Order Service Outage**: Payment Service logs state + Transactional Outbox event in single local SQL transaction. Kafka retains event. When Order Service boots up, idempotent consumer (`UNIQUE(reservation_id)`) creates order cleanly. Data loss = 0%.
- **Payment Failures**: Triggers atomic Lua release script; stock returned to pool.
- **Transient Network Errors**: Full Jitter Exponential Backoff retries on idempotent endpoints only.

---

### Slide 6: Scaling & Backpressure
- **Stateless Microservice Scaling**: Kubernetes HPA auto-scales pods on CPU / Kafka lag.
- **Hot-Product Key Protection**: Redis hash tags `{product_1001}` allocate hot product keys to dedicated cluster master shards; non-mutating reads offloaded to 16 read replicas.
- **PgBouncer Multiplexing**: PgBouncer transaction pooling limits PostgreSQL active connections to safe server limits.

---

### Slide 7: Security & Observability
- **Security**: OAuth2 + RS256 JWT validation at Envoy Gateway, mTLS microservice mesh, Vault secret injection, PCI-DSS tokenization (no raw cards stored).
- **Observability**: OpenTelemetry RED (Rate, Errors, Duration) & USE metrics in Prometheus, W3C distributed tracing in Grafana Tempo, LogSanitizer PII scrubbing in Loki, WORM S3 Glacier audit archive.

---

### Slide 8: Key Guarantees & Trade-offs
- **Key Guarantees**:
  1. No overselling (`inventory_quantity >= 0`).
  2. Duplicate-safe (`UNIQUE(idempotency_key)`).
  3. Expiry-safe & Payment-safe.
  4. Recoverable order workflow via Transactional Outbox.
- **Trade-offs**:
  1. Redis Lua fast-path and PostgreSQL durable store have a non-atomic dual-write boundary (reconciled via sweepers).
  2. Redis replication is asynchronous; during uncertain Redis failover, system **fails closed** (503 response) to prevent unsafe reservations.
