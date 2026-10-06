# Architecture Decision Record (ADR)
## ADR-005: Transactional Outbox Pattern for Surviving Temporary Order Service Outages

---

### Status
**ACCEPTED**

### Context
If a customer's payment succeeds at the Payment Gateway, but the downstream Order Service is unavailable for 30 seconds (due to pod restarts or network partitions), the system must recover automatically without losing orders or charging users without creating orders.

---

### Problem
Synchronous RPC calls from Payment Service to Order Service fail if Order Service is down. Direct message publishing to Kafka during SQL transactions risks lost events if Kafka is unreachable during SQL `COMMIT`.

---

### Decision
We adopt the **Transactional Event Outbox Pattern**:
1. Within a single local PostgreSQL transaction, Payment Service updates payment status to `CONFIRMED` and inserts an event record into `outbox_events`.
2. A separate background outbox poller publishes `salestorm.payment.completed` to Kafka.
3. Message remains durable in Kafka until Order Service recovers.
4. Order Service consumer is idempotent (`UNIQUE(reservation_id)` in PostgreSQL).

---

### Why This Decision
- **Decoupled Availability**: Temporary Order Service outages do not block Payment Service or fail user checkouts.
- **At-Least-Once Delivery**: Outbox guarantees event delivery without lost updates.
- **Idempotent Recovery**: When Order Service recovers, duplicate event deliveries execute safely without creating extra order records.
