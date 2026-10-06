# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 07: Failure Recovery Protocols — Order Service Outage & Transactional Outbox

---

### 1. Payment Success + 30-Second Order Service Outage Recovery

#### Scenario Description
1. User completes payment successfully at third-party Payment Gateway.
2. Payment Service receives webhook and updates local database state to `CONFIRMED`.
3. **CRASH**: Order Service is unavailable for 30 seconds (pod restart or network partition).

```
[ Payment Service ] 
         |
         +--> Local SQL Transaction: 
         |    - UPDATE payment status = 'CONFIRMED'
         |    - INSERT INTO outbox_events (type = 'PaymentCompleted', payload)
         |    - COMMIT
         |
         +--> Kafka Topic `salestorm.payment.completed`
                     |
                     X (Order Service DOWN for 30s)
                     |
         +-----------+-----------------------------------+
         | RECOVERY PROTOCOL INITIATED                    |
         +-----------------------------------------------+
         | 1. Payment Service outbox event stays durable |
         | 2. Kafka retains message on partition         |
         | 3. At T = 30s, Order Service Pod restarts    |
         | 4. Consumer group resumes from offset        |
         | 5. Order Service inserts order idempotently  |
         |    via SQL `UNIQUE(reservation_id)`          |
         +-----------------------------------------------+
```

#### Idempotent Order Consumer Guard
When Order Service recovers, it processes pending Kafka events using SQL unique constraints:

```sql
INSERT INTO orders (id, reservation_id, user_id, status) 
VALUES ('ord_123', 'res_9981', 'usr_441', 'CONFIRMED')
ON CONFLICT (reservation_id) DO NOTHING;
```

**Guarantee**: Temporary Order Service outages do NOT block Payment Service, cause dropped orders, or create duplicate order records.
