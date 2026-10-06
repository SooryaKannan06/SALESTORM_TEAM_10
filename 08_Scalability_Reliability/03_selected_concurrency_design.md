# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 03: Selected Concurrency Design — Redis Lua Fast-Path & Dual-Write Reconciliation

---

### 1. Selected Concurrency Design Philosophy

SALESTORM implements a **Hybrid Two-Tier Memory-First Concurrency Model**. Fast-path inventory validation and reservation decisions execute in-memory via single-threaded, atomic Lua scripts in Redis Cluster. A secondary pipeline writes durable records to PostgreSQL.

> [!IMPORTANT]
> **CRITICAL ARCHITECTURAL DISTINCTION: NON-ATOMIC DUAL-WRITE BOUNDARY**  
> Redis Lua execution and PostgreSQL database writes do NOT constitute a single distributed atomic transaction. Redis provides high-speed atomic admission decisions, while PostgreSQL serves as the durable source of truth.

---

### 2. Dual-Write Limitation & Reconciliation Worker

```
[ User Request ]
       |
       v
[ Redis Atomic Lua Fast-Path ] -------------> [ SUCCESS: Stock Decremented ]
       |                                                    |
       v                                                    v
[ Inventory Service App Pod ]                      App Node Crashes Before DB Write!
       |                                                    |
       v                                                    v
[ PostgreSQL Write Attempt ]                     [ Redis Trigger Key Active (10m TTL) ]
       |                                                    |
   (CRASH!)                                      [ Expiration Sweeper Worker ]
       |                                                    |
       x                                         Detects missing SQL record
                                                 Executes Lua INCRBY (+1 Stock)
```

#### Discrepancy Reconciliation Protocol
If Redis reservation succeeds but application node dies *before* PostgreSQL persistence:
1. Redis reservation key has a 10-minute TTL trigger key (`salestorm:expire_trigger:res_9981`).
2. If no payment confirmation or PostgreSQL DB sync occurs within 10 minutes, the **Auto-Release Sweeper** detects an unconfirmed Redis reservation without a matching DB record and executes a compensating Redis stock increment (`INCRBY stock_key qty`).

---

### 3. Redis Failover Policy: Fail-Closed

Redis replication is asynchronous. During a primary Redis master node crash:
1. Replicas promoted to Master may lack the latest un-replicated Lua decrements if replication lag exists.
2. **Fail-Closed Rule**: During an uncertain Redis failover or cluster split-brain state, SALESTORM **fails closed** (returns HTTP 503 retryable service unavailable response) rather than granting potentially unsafe inventory.
3. Upon cluster stabilization, background reconciliation sweepers rebuild Redis inventory counters from persistent PostgreSQL durable records before re-opening flash-sale checkouts.

---

### 4. Production Redis Lua Reservation Script

```lua
-- ============================================================================
-- SALESTORM ATOMIC INVENTORY RESERVATION LUA SCRIPT
-- ============================================================================
-- KEYS[1]: Stock Key            e.g. salestorm:{prod_1001}:stock
-- KEYS[2]: Reservations Hash    e.g. salestorm:{prod_1001}:reservations
-- ARGV[1]: User ID              e.g. usr_99812
-- ARGV[2]: Quantity Requested   e.g. 1
-- ARGV[3]: Idempotency Key      e.g. idem_req_7781a
-- ARGV[4]: Reservation TTL (s)  e.g. 600 (10 minutes)
-- ARGV[5]: Timestamp            e.g. 1769938000
-- ============================================================================

local stock_key = KEYS[1]
local res_hash_key = KEYS[2]

local user_id = ARGV[1]
local req_qty = tonumber(ARGV[2])
local idem_key = ARGV[3]
local ttl_seconds = tonumber(ARGV[4])
local current_time = tonumber(ARGV[5])

-- STEP 1: Idempotency Check
local existing_res = redis.call("HGET", res_hash_key, idem_key)
if existing_res then
    return cjson.encode({
        status = "DUPLICATE_REQUEST",
        code = 200,
        data = cjson.decode(existing_res)
    })
end

-- STEP 2: Stock Balance Verification
local current_stock = tonumber(redis.call("GET", stock_key) or "0")

if current_stock < req_qty then
    return cjson.encode({
        status = "SOLD_OUT",
        code = 409,
        message = "Insufficient inventory available for reservation"
    })
end

-- STEP 3: Atomic Stock Decrement
local remaining_stock = redis.call("DECRBY", stock_key, req_qty)

-- Safety Guard: Invariant state check
if remaining_stock < 0 then
    redis.call("INCRBY", stock_key, req_qty)
    return cjson.encode({
        status = "SOLD_OUT",
        code = 409,
        message = "Stock depleted during evaluation"
    })
end

-- STEP 4: Store Reservation Payload
local reservation_id = "res_" .. tostring(current_time) .. "_" .. tostring(redis.call("INCR", "salestorm:global:res_counter"))

local reservation_payload = {
    reservation_id = reservation_id,
    user_id = user_id,
    quantity = req_qty,
    status = "RESERVED",
    created_at = current_time,
    expires_at = current_time + ttl_seconds,
    idempotency_key = idem_key
}

redis.call("HSET", res_hash_key, idem_key, cjson.encode(reservation_payload))

return cjson.encode({
    status = "SUCCESS",
    code = 201,
    data = reservation_payload,
    remaining_stock = remaining_stock
})
```
