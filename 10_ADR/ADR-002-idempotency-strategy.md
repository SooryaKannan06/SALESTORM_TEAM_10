# Architecture Decision Record (ADR)
## ADR-002: Two-Tier Idempotency Strategy for Purchase Submissions and Payment Processing

---

### Status
**ACCEPTED**

### Context
During flash sales, aggressive user UI clicks and network retries produce an estimated 2% duplicate request flood (200 duplicate requests out of 10,000). Duplicate requests must not create duplicate reservations or double-charge users.

---

### Problem
Relying solely on in-memory locks can fail if cache keys expire or nodes fail over. Relying solely on database unique constraints causes unneeded database queries for every duplicate request.

---

### Options Considered
1. **Option A: Database Unique Constraints Only**
2. **Option B: Gateway Redis Locks Only**
3. **Option C: Two-Tier Idempotency (Redis Fast Filter + PostgreSQL Unique Index) (Selected)**

---

### Decision
We adopt **Option C: Two-Tier Idempotency Architecture**:
- **Purchase Idempotency**: Clients supply `Idempotency-Key: BUY-<user>-<product>-<nonce>`. API Gateway checks Redis (`SET key IN_PROGRESS NX EX 10`). PostgreSQL enforces `UNIQUE(idempotency_key)` as the durable source of truth.
- **Payment Idempotency**: Payment Service uses a unique transaction reference `payment_id = PAY-<reservation_id>-<nonce>` passed to payment providers.

---

### Why This Decision
- **Latency Protection**: 200 duplicate requests are filtered in <1.5ms at Redis without hitting the database.
- **Durable Correctness**: PostgreSQL unique indices prevent duplicate records even if Redis keys expire prematurely.

---

### Trade-offs & Consequences
- Clients must generate and pass unique `Idempotency-Key` headers on state-changing API endpoints.
