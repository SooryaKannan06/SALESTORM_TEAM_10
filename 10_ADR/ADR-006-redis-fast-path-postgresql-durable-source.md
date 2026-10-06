# Architecture Decision Record (ADR)
## ADR-006: Defining Source of Truth and Dual-Write Reconciliation between Redis and PostgreSQL

---

### Status
**ACCEPTED**

### Context
Redis in-memory Lua execution provides high-speed inventory admission decisions during flash sales, while PostgreSQL provides durable persistent business records. Because Redis and PostgreSQL are independent data stores, they do NOT share a single atomic transaction boundary.

---

### Decision & Source of Truth Definition
1. **Flash Sale Hot-Path Source of Truth**: During active flash-sale execution, **Redis Cluster in-memory state is the single authority for atomic admission decisions**.
2. **Durable Business Source of Truth**: **PostgreSQL is the permanent source of truth** for financial audit, persistent reservations, and order fulfillment records.
3. **Non-Atomic Dual-Write Mitigation**:
   - If Redis succeeds but application node dies before PostgreSQL write: The reservation remains in Redis. If unconfirmed after 10 minutes, the Expiration Sweeper detects missing SQL reservation and executes an atomic Lua stock restoration (`INCRBY stock_key qty`).
   - **Fail-Closed on Redis Failover**: Because Redis async replication can lag, during uncertain Redis failover, system **fails closed** (returns 503 retryable responses) until Redis memory state is reconciled against PostgreSQL durable records.

---

### Trade-offs & Consequences
- Explicitly acknowledges distributed dual-write boundaries rather than making impossible atomic transaction claims.
- Guarantees zero-overselling through fail-closed failover policies.
