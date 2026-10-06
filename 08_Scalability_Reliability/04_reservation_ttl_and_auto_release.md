# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 04: Reservation TTL Engine & Automatic Inventory Release

---

### 1. Business Need & Reservation Lifecycle

When a customer successfully reserves stock during a flash sale, holding that unit indefinitely creates an abandoned cart bottleneck. SALESTORM enforces a **10-minute (600 seconds) Reservation TTL**.

```
                  +----------------------------------------------+
                  |                 AVAILABLE                    |
                  +----------------------------------------------+
                                         |
                       Reserve Stock (Lua Script)
                                         v
                  +----------------------------------------------+
                  |                 RESERVED                     |
                  |             (TTL = 600 seconds)              |
                  +----------------------------------------------+
                                 /               \
              Payment Initiated /                 \ TTL Expired / User Abandons
                               v                   v
+-----------------------------------+     +-----------------------------------+
|          PAYMENT_PENDING          |     |             RELEASED              |
+-----------------------------------+     |   (Stock restored via Lua INCR)   |
          /               \               +-----------------------------------+
   Success /                 \ Failure / Timeout
          v                   v
+-------------------+     +-------------------+
|     CONFIRMED     |     |     RELEASED      |
+-------------------+     +-------------------+
          |
   Fulfillment
          v
+-------------------+
|       SOLD        |
+-------------------+
```

---

### 2. Simplified TTL Architecture: Primary Redis TTL + SQL Sweeper

Rather than introducing redundant infrastructure complexity:

1. **Primary Mechanism**: Redis TTL key expiration + atomic Lua release script.
2. **Safety Net**: Periodic background sweeper querying PostgreSQL durable reservation records (`WHERE status = 'RESERVED' AND expires_at < NOW()`).
3. **Idempotency Rule**: Inventory release is strictly idempotent. Executing release twice restores stock balance exactly once (`INCRBY 1`).

---

### 3. Expiry vs Payment Race Condition Rule

> [!IMPORTANT]
> **DETERMINISTIC EXPIRY VS PAYMENT RULE**:  
> Only a valid, unexpired reservation in `RESERVED` state can transition to `CONFIRMED`.  
> If payment succeeds *after* the reservation has already expired and transitioned to `RELEASED`:  
> - Payment success MUST NOT recreate the reservation or decrement stock.  
> - An automated refund/compensation workflow is triggered to refund the customer's payment.

```
Time         Payment Service Thread                  Expiration Sweeper Thread
--------------------------------------------------------------------------------------
T = 599.9s   Receives Payment SUCCESS webhook
T = 600.0s   Executes DB UPDATE -> CONFIRMED
             Attempts Redis Lua status update         Fires Expiration Sweeper
T = 600.1s   Lua checks res.status                    Executes Release Lua Script
             State = CONFIRMED                       Sees res.status = CONFIRMED
             Updates state to CONFIRMED               ABORTS release (Stock NOT incr)
```
