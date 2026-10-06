# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 02: Deep-Dive Analysis — Pessimistic vs Optimistic Concurrency vs In-Memory Atomic Execution

---

### 1. Introduction & Objectives

Choosing the appropriate concurrency control mechanism for inventory reservation during a high-scale flash sale is a pivotal architectural decision. This document provides a rigorous quantitative and qualitative comparison of four major concurrency control strategies:

1. **Pessimistic Locking** (`SELECT ... FOR UPDATE` in RDBMS)
2. **Optimistic Locking** (CAS / Version Column update in RDBMS)
3. **Queue-Based Serialized Processing** (Kafka / RabbitMQ Single Consumer Partitioning)
4. **In-Memory Atomic Lua Scripting** (Redis Cluster — **Selected Architecture**)

---

### 2. Deep-Dive Strategy Comparison

#### 2.1 Strategy A: Pessimistic Locking (`SELECT FOR UPDATE`)

##### Mechanism
The transaction locks the target inventory row exclusively at the SQL layer before reading or updating stock:

```sql
BEGIN;
SELECT available_stock FROM inventory 
WHERE product_id = 'prod-x' FOR UPDATE;

-- Application checks: available_stock >= 1
UPDATE inventory 
SET available_stock = available_stock - 1, 
    reserved_stock = reserved_stock + 1 
WHERE product_id = 'prod-x';

INSERT INTO reservations (id, user_id, product_id, status) 
VALUES ('res-123', 'user-456', 'prod-x', 'RESERVED');
COMMIT;
```

##### Failure Modes & Bottlenecks under 10,000 Concurrent Requests
- **DB Lock Contention**: All 10,000 requests contend for a single row lock on `product_id = 'prod-x'`. Requests $2 \dots 10,000$ enter PostgreSQL lock wait state (`pg_stat_activity` state = `active`, wait_event = `Lock:transactionid`).
- **Connection Pool Exhaustion**: Connection pool HikariCP (typically sized at 50-100 connections) is depleted in under 10 milliseconds. Subsequent HTTP requests fail with `HikariPool-1 - Connection is not available, request timed out after 3000ms`.
- **Deadlock Potential**: If concurrent updates touch associated tables (e.g., user account limits or audit logs) in non-identical ordering, RDBMS detects deadlocks and aborts transactions (`SQLState 40P01`).

##### Mathematical Throughput & Latency Model
Let average row-lock hold time (including network round-trip, query execution, and commit flush) be $T_h = 15\text{ ms}$.

Maximum theoretical throughput $Q_{max}$ for a single hot inventory row:

$$Q_{max} = \frac{1}{T_h} = \frac{1}{0.015\text{ s}} \approx 66.67 \text{ req/sec}$$

For 10,000 requests, total processing time for the queue:

$$T_{total} = 10,000 \times 0.015\text{ s} = 150 \text{ seconds}$$

**Verdict**: Unusable for flash sales. 99% of users suffer HTTP timeouts (>30 seconds).

---

#### 2.2 Strategy B: Optimistic Locking (Compare-And-Swap / Versioning)

##### Mechanism
Transactions read stock without acquiring row locks. Updates succeed only if the version column or stock value remains unchanged since the read:

```sql
-- Read initial state
SELECT available_stock, version FROM inventory WHERE product_id = 'prod-x';

-- Attempt conditional update
UPDATE inventory 
SET available_stock = available_stock - 1,
    version = version + 1
WHERE product_id = 'prod-x' 
  AND version = :initial_version 
  AND available_stock >= 1;
```

##### Failure Modes & Bottlenecks under 10,000 Concurrent Requests
- **High Abort Rate (Retry Storm)**: When 10,000 threads execute the `UPDATE` concurrently, exactly 1 thread succeeds per version increment. The remaining 9,999 threads fail with 0 rows updated (`optimistic lock exception`).
- **Wasted Compute & DB IOPS**: Re-trying failed operations causes massive CPU utilization on application nodes and RDBMS. If retried 10 times per request, $100,000$ DB write queries are generated for 100 stock items.

##### Retry Probability Equation
For $N$ concurrent competing requests on version $v$:

$$P(\text{Success for single request}) = \frac{1}{N}$$

$$P(\text{Failure rate}) = 1 - \frac{1}{N} = \frac{N-1}{N} \quad (\text{For } N = 10,000, \text{ Failure Rate} = 99.99\%)$$

**Verdict**: Excellent for low contention; disastrous for flash sales with extreme hotspot contention.

---

#### 2.3 Strategy C: Queue-Based Serialized Processing

##### Mechanism
All purchase requests are pushed to a message broker (e.g., Apache Kafka partition keyed by `product_id`). A single thread consumer reads messages sequentially and applies balance updates.

```
[ 10,000 Requests ] ---> [ Kafka Topic: buy-requests (Partition 0) ]
                                      |
                                      v
                        [ Single Thread Consumer Worker ]
                                      |
                         (Executes Stock Check & Reserve)
```

##### Trade-offs & Limitations
- **Pros**: 0% overselling, predictable execution, no DB lock contention.
- **Cons**: High client latency (users wait in polling state for asynchronous queue consumer processing), queuing delay during sudden traffic spikes, complex asynchronous user interface contract (WebSockets / Server-Sent Events / Long Polling required).

---

#### 2.4 Strategy D: In-Memory Atomic Lua Scripting (SALESTORM Selected Architecture)

##### Mechanism
Inventory balances are maintained in Redis Cluster. Atomic Lua scripts combine conditional read, validation, subtraction, and reservation log creation into a **single, non-preemptible operation** executed in Redis single-threaded execution context per shard.

```lua
-- Redis Lua Atomic Decrement & Reservation Script
-- KEYS[1]: inventory_key ({product_x}:stock)
-- KEYS[2]: reservation_key ({product_x}:reservations)
-- ARGV[1]: user_id
-- ARGV[2]: request_qty
-- ARGV[3]: idempotency_key
-- ARGV[4]: ttl_seconds

-- 1. Idempotency Check
if redis.call("HEXISTS", KEYS[2], ARGV[3]) == 1 then
    return redis.call("HGET", KEYS[2], ARGV[3]) -- Return existing reservation JSON
end

-- 2. Stock Balance Check
local current_stock = tonumber(redis.call("GET", KEYS[1]) or "0")
local req_qty = tonumber(ARGV[2])

if current_stock < req_qty then
    return cjson.encode({status = "SOLD_OUT", code = 409})
end

-- 3. Atomic Execution
redis.call("DECRBY", KEYS[1], req_qty)

local reservation_id = "res_" .. redis.call("INCR", "global:res_seq")
local payload = cjson.encode({
    reservation_id = reservation_id,
    user_id = ARGV[1],
    qty = req_qty,
    status = "RESERVED",
    created_at = redis.call("TIME")[1]
})

redis.call("HSET", KEYS[2], ARGV[3], payload)
redis.call("SETEX", "res_expire:" .. reservation_id, ARGV[4], ARGV[3])

return payload
```

##### Latency & Throughput Metrics
- Average Redis Lua Execution Time: **0.35ms - 0.8ms**.
- Single Redis Shard Throughput: **~45,000 - 85,000 ops/sec**.
- Latency for 10,000 concurrent requests across API cluster: **P95 < 12ms, P99 < 35ms**.

---

### 3. Summary Comparison Matrix

| Technical Criterion | Pessimistic Locking | Optimistic Locking | Queue Serialized | In-Memory Lua (Selected) |
| :--- | :--- | :--- | :--- | :--- |
| **Concurrency Latency (P99)** | > 3,000 ms (Timeout) | > 1,500 ms (Retries) | 200 ms - 1,000 ms | **< 35 ms** |
| **Maximum Throughput** | ~50 - 100 req/s | ~500 - 1,200 req/s | ~5,000 req/s | **> 50,000 req/s** |
| **DB Connection Load** | Critical Saturation | High CPU / IOPS | Low | Zero (Hot Path) |
| **Client UX Feedback** | Synchronous Timeout | Synchronous Retry | Async Polling | **Synchronous Instant** |
| **Oversell Risk** | 0% | 0% | 0% | **0%** |
| **Architectural Complexity** | Low | Low | Medium-High | Medium |

---

### 4. Trade-Off Justification

The **In-Memory Atomic Lua Scripting** approach is selected because flash sales prioritize extreme concurrency performance, sub-50ms user responsiveness, and strict zero-overselling. By offloading hot-path concurrency checks from disk-bound SQL databases to single-threaded memory structures in Redis, SALESTORM handles 10,000 concurrent purchase attempts for 100 units cleanly in milliseconds, rejecting the 9,900 unsuccessful requests instantly without degrading system infrastructure.
