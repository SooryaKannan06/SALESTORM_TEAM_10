# Architecture Decision Record (ADR)
## ADR-003: Simplified Dual-Tier Reservation TTL Expiration & Idempotent Auto-Release Engine

---

### Status
**ACCEPTED**

### Context
When stock is reserved, holding it indefinitely creates abandoned cart bottlenecks. A 10-minute reservation TTL window is enforced. Expiration must release inventory safely back to available stock.

---

### Problem
Pure Redis key expiration events are pub/sub fire-and-forget; if worker pods restart during key expiration, events are missed. Conversely, relying solely on heavy SQL polling sweepers creates database IOPS overhead.

---

### Decision
We implement a **Simplified Dual-Tier Expiration Engine**:
1. **Primary Mechanism**: Redis TTL key expiration + atomic Lua release script.
2. **Safety Net**: Periodic background sweeper verifying durable PostgreSQL reservation records (`WHERE status = 'RESERVED' AND expires_at < NOW()`).
3. **Idempotency Rule**: Inventory release is strictly idempotent. Re-executing release on an already released or confirmed reservation is a no-op (`INCRBY` executed once).
4. **Expiry vs Payment Race Rule**: Only a valid, unexpired reservation can transition to `CONFIRMED`. If a reservation is already `RELEASED`, payment completion triggers an automated refund/compensation process.

---

### Trade-offs & Consequences
- Ensures stock from abandoned carts is returned to available pool within 10 minutes.
- Prevents double-release bugs via single-threaded Redis Lua status checking.
