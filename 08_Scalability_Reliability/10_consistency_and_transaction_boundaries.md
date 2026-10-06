# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 10: Consistency Models, Transaction Boundaries & Saga Orchestration

---

### 1. Architectural Consistency Philosophy

In a high-scale microservices system, enforcing synchronous 2-Phase Commit (2PC) or distributed ACID transactions across network boundaries causes extreme latency, lock deadlocks, and availability drops (CAP theorem constraint).

SALESTORM implements a **Hybrid Consistency Model**:
- **Local Consistency**: ACID guarantees inside individual microservice database boundaries (PostgreSQL local transactions).
- **Global Consistency**: BASE (Basically Available, Soft-state, Eventual consistency) managed via **Event-Driven Saga Pattern** with **Transactional Outbox**.

---

### 2. Microservice Transaction Boundaries

```
+-------------------+      +-------------------+      +-------------------+
| Inventory Service |      |  Payment Service  |      |   Order Service   |
| (PostgreSQL DB 1) |      | (PostgreSQL DB 2) |      | (PostgreSQL DB 3) |
+-------------------+      +-------------------+      +-------------------+
  Local ACID Boundary        Local ACID Boundary        Local ACID Boundary
          |                          |                          |
          +--------------------------+--------------------------+
                                     |
                       Global BASE Consistency Scope
                       (Kafka Event-Driven Saga)
```

---

### 3. Saga Pattern Design: Choreography vs Orchestration

SALESTORM adopts **Choreographed Event-Driven Saga** for fast-path flash sale flow due to lower latency overhead, backed by an **Orchestrated Saga Fallback Coordinator** for edge-case recovery.

```
[ Inventory Service ]
   |
   +-- Local DB Tx: Reservation = RESERVED
   +-- Outbox Event: `salestorm.reservation.created`
          |
          v (Kafka Topic)
[ Payment Service ]
   |
   +-- Consumes `salestorm.reservation.created`
   +-- Process Payment Gateway Charge
   +-- Local DB Tx: Payment = CONFIRMED
   +-- Outbox Event: `salestorm.payment.completed`
          |
          v (Kafka Topic)
[ Order Service ]
   |
   +-- Consumes `salestorm.payment.completed`
   +-- Local DB Tx: Order = CREATED -> CONFIRMED
```

---

### 4. Compensation Matrix for Failure Scenarios

When a step in the Saga fails, **Compensating Transactions** execute in reverse order to restore system consistency:

| Initiating Failure | Detecting Service | Saga State Transition | Compensating Action |
| :--- | :--- | :--- | :--- |
| **Payment Failed (Card Decline)** | Payment Service | `RESERVED` -> `PAYMENT_FAILED` | Publish `payment.failed` event -> Inventory Service restores Redis & DB stock balance (`+1`). |
| **Payment Timeout (No Gateway Resp)**| Payment Service | `RESERVED` -> `PAYMENT_TIMEOUT` | Trigger Gateway Status Check -> If unpaid, trigger stock release; if paid, confirm order. |
| **Reservation Expired (10m TTL)** | Expiration Worker | `RESERVED` -> `RELEASED` | Execute Redis Lua release script -> Restores stock balance (`+1`). |
| **Order Service DB Outage** | Order Service | `CONFIRMED` -> `RETRY_PENDING` | Outbox Sweeper retries until Order Service recovers -> Idempotent order creation. |

---

### 5. Transactional Outbox Pattern Implementation

To eliminate dual-write inconsistencies between database mutations and Kafka message publishing, all state changes write to an **Outbox Table** within the exact same database transaction:

```sql
-- Step 1: Execute Local Business Logic & Write Event inside single SQL transaction
BEGIN;

UPDATE reservations 
SET status = 'CONFIRMED', updated_at = NOW() 
WHERE id = 'res_99812' AND status = 'RESERVED';

INSERT INTO outbox_events (
    event_id, 
    aggregate_type, 
    aggregate_id, 
    event_type, 
    payload, 
    status, 
    created_at
) VALUES (
    gen_random_uuid(), 
    'RESERVATION', 
    'res_99812', 
    'RESERVATION_CONFIRMED', 
    '{"reservation_id": "res_99812", "user_id": "usr_441", "product_id": "prod_1001"}', 
    'PENDING', 
    NOW()
);

COMMIT;
```

#### Outbox Event Publisher Poller (Debezium / Custom Worker)
A lightweight background process reads uncommitted events:

```sql
SELECT * FROM outbox_events 
WHERE status = 'PENDING' 
ORDER BY created_at ASC 
LIMIT 100 FOR UPDATE SKIP LOCKED;
```

1. Reads 100 batch events.
2. Publishes messages to Kafka topic `salestorm.inventory.events`.
3. Updates `status = 'PROCESSED'` in outbox table.
4. If Kafka write fails, event remains `PENDING` and is retried.

**Guarantee**: At-Least-Once event delivery across service boundaries with 0% dropped state changes.
