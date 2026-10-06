# Architecture Decision Record (ADR)
## ADR-001: Selection of Redis Atomic Execution for High-Concurrency Fast-Path Inventory Reservation

---

### Status
**ACCEPTED**

### Context
SALESTORM is designed for a flash-sale scenario where Product X has 100 available units and 10,000 customers simultaneously attempt to purchase. The system must guarantee that successful reservations never exceed 100 (`successful_reservations <= 100`) and stock balance never becomes negative (`inventory_quantity >= 0`).

---

### Problem
Traditional PostgreSQL row locking (`SELECT ... FOR UPDATE`) under 10,000 concurrent threads creates extreme lock contention on a single row, exhausting database connection pools (`HikariCP`) within milliseconds and causing client timeouts. Optimistic locking (`@Version` / CAS updates) causes a 99.9% abort rate and wasted CPU retries.

---

### Options Considered
1. **Option A: PostgreSQL Pessimistic Row Locking (`SELECT FOR UPDATE`)**
2. **Option B: PostgreSQL Optimistic Locking (Version Column update)**
3. **Option C: Redis Atomic Script Execution (Fast-Path) + PostgreSQL Durable Storage (Selected)**

---

### Decision
We select **Option C: Redis Atomic Script Execution (Fast-Path) + PostgreSQL Durable Storage**.

Redis single-threaded Lua script execution evaluates conditional stock availability and decrements inventory atomically on hash-tagged key slots (`{product_1001}`). Redis acts as the high-speed admission filter for the flash sale, while PostgreSQL stores durable reservation records.

---

### Why This Decision
- **Atomicity**: Prevents race conditions and lost updates without disk-bound row locking.
- **Fast Failure**: The 9,900 losing requests are rejected instantly in-memory (<2ms) without touching the relational database.
- **Scalability**: Decouples fast-path reservation checks from disk I/O bottlenecks.

---

### Trade-offs & Limitations
- **Dual-Write Boundary**: Redis in-memory reservation state and PostgreSQL durable storage are NOT a single distributed ACID transaction. Application crashes between Redis success and SQL write must be handled by background reconciliation sweepers.
- **Redis Failover Risk**: Redis replication is asynchronous. During Redis cluster failover, the system fails closed (rejects new reservations until state is reconciled against PostgreSQL).

---

### Rejected Alternatives
- **Pessimistic DB Locking**: Rejected due to connection pool exhaustion and >2500ms P99 latency under 10k concurrency.
- **Optimistic DB Locking**: Rejected due to catastrophic retry storms under hot-spot contention.
