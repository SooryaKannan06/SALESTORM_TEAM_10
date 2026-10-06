    # SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 01: High-Concurrency Inventory Reservation Strategy

---

### 1. Architectural Overview & Context

In high-scale e-commerce flash sales, inventory reservation represents the most concurrency-sensitive boundary in the system. When 10,000 customers simultaneously attempt to purchase a constrained stock item (Product X with **100 available units**), traditional relational database transactions fail due to row lock contention, connection pool exhaustion, and thread starvation.

The primary objective of the SALESTORM Inventory Concurrency Strategy is to enforce a **0% overselling guarantee** while maintaining low user-perceived latency and high admission throughput.

```
+-----------------------------------------------------------------------------------+
|                                 SALESTORM EDGE ADMISSION                          |
|   10,000 Concurrent Requests -> [ API Gateway / Virtual Waiting Room ]            |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
|                        ATOMIC INVENTORY RESERVATION ENGINE                        |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  | Redis Cluster (Fast-Path In-Memory Atomic Layer)                           |  |
|  | - Hash Tag: {product_1001} (Ensures single-slot execution)                 |  |
|  | - Lua Script: Stock check + DECRBY + Idempotency Check                      |  |
|  +-----------------------------------------------------------------------------+  |
|                                         |                                         |
|                 +-----------------------+-----------------------+                 |
|                 | Reservation SUCCESS                           | Reservation FAIL|
|                 v                                               v                 |
|  +-------------------------------------+             +-------------------------+  |
|  | PostgreSQL (Durable Store of Truth) |             | HTTP 409 Conflict       |  |
|  | - Transactional Outbox Event        |             | "Sold Out" Graceful     |  |
|  | - State: RESERVED                   |             | Response                |  |
|  +-------------------------------------+             +-------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

### 2. Core Invariants & Mathematical Rules

To eliminate overselling and state corruption, SALESTORM strictly enforces three mathematical invariants:

1. **Reservation Bound**:
   $$\text{successful\_reservations} \le \text{available\_inventory} \quad (\text{At most 100 reservations can succeed initially})$$

2. **Order Bound**:
   $$\text{successful\_orders} \le \text{successfully\_confirmed\_reservations} \quad (\text{At most 100 final sales can succeed})$$

3. **Non-Negative Balance**:
   $$\text{inventory\_quantity} \ge 0 \quad (\text{Inventory quantity never becomes negative under any branch})$$

> [!NOTE]
> Actual successful orders may be lower than 100 if user payments fail or reservations expire without payment.

---

### 3. High-Concurrency Race Condition Analysis

When multiple execution threads read, check, and update stock balances concurrently without strict synchronization, severe data anomaly classes emerge:

#### 3.1 Lost Update / Double Allocation
Two concurrent processes ($P_1$ and $P_2$) accessing an un-synchronized database row for Product X with `stock = 1`:

$$\begin{array}{rcc l}
\text{Time} & P_1 \text{ Action} & P_2 \text{ Action} & \text{Database State} \\
\hline
T_1 & \text{READ stock (1)} & - & \text{stock} = 1 \\
T_2 & - & \text{READ stock (1)} & \text{stock} = 1 \\
T_3 & \text{Check } 1 \ge 1 \rightarrow \text{OK} & - & \text{stock} = 1 \\
T_4 & - & \text{Check } 1 \ge 1 \rightarrow \text{OK} & \text{stock} = 1 \\
T_5 & \text{WRITE stock = 0} & - & \text{stock} = 0 \quad (\text{Order } O_1 \text{ created}) \\
T_6 & - & \text{WRITE stock = 0} & \text{stock} = 0 \quad (\text{Order } O_2 \text{ created}) \\
\end{array}$$

**Outcome**: Both $O_1$ and $O_2$ are confirmed for a single physical item. **Stock oversold by 1 unit.**

#### 3.2 Database Lock Contention & Thread Starvation
If relational database row-level locking (`SELECT ... FOR UPDATE`) is applied under 10,000 concurrent threads:
- $P_1$ acquires exclusive lock on row `product_1001`.
- $P_2 \dots P_{10000}$ enter PostgreSQL lock wait queue.
- Connection pools (`HikariCP`) saturate in milliseconds. HTTP threads block, leading to cascading timeouts.

---

### 4. Comparison of Concurrency Paradigms

| Strategy | Atomicity Primitive | Contention Handling | Latency Profile | Overselling Risk | Architectural Target |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Pessimistic Locking (RDBMS)** | `SELECT FOR UPDATE` | High Lock Wait / Saturation | High Latency (>2500ms) | 0% (Guaranteed) | Unsuitable for flash sales |
| **Optimistic Locking (RDBMS)** | `UPDATE ... WHERE version=N` | 99.9% Retry Abort Rate | High CPU Retries | 0% (Guaranteed) | Unsuitable for hot-spots |
| **Redis Lua Fast-Path (Selected)** | Single-Threaded Atomic Lua | In-Memory Fast Filter | Low Latency Target (<50ms) | 0% (Guaranteed) | **Selected Fast-Path Engine** |

---

### 5. Selected Hybrid Architecture: Atomic Fast-Path + Durable Source of Truth

SALESTORM adopts a **Two-Tier Concurrency Model**:

1. **Tier 1: Atomic Fast-Path (Redis Cluster)**
   - Redis executes single-threaded Lua scripts on dedicated key hash tags (`{product_1001}`).
   - Checks user idempotency, verifies balance, decrements stock atomically, and logs transient reservation state.
   - Rejects excess losing requests instantly in-memory without hitting the database.

2. **Tier 2: Durable Source of Truth (PostgreSQL)**
   - Stores durable reservation records, payment transactions, and order history.
   - Dual-write boundary between Redis and PostgreSQL is reconciled via background sweepers.
