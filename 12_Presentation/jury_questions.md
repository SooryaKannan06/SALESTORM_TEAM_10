# SALESTORM — Module 4: Hackathon Jury Q&A Defense Handbook

---

### Question 1: "Why Redis atomic reservation?"
**Answer**: Because single-threaded Lua script execution in Redis cluster shards evaluates inventory balance and decrements stock in a single atomic step in-memory (<2ms). This filters out losing requests instantly without disk I/O.

---

### Question 2: "Why not simply use a database row lock?"
**Answer**: Under 10,000 concurrent requests, `SELECT ... FOR UPDATE` on a single database row causes severe lock contention, saturates connection pools (HikariCP) in 10ms, and causes client timeouts (>2500ms P99).

---

### Question 3: "Why not simply use optimistic DB locking?"
**Answer**: Optimistic locking (`WHERE version = N`) causes a 99.9% abort rate under 10,000 concurrent threads competing for a single version counter, resulting in massive CPU waste and retry storms.

---

### Question 4: "What happens if two users request the last unit?"
**Answer**: Redis processes Lua scripts sequentially per shard. The first user's execution decrements stock from 1 to 0 and returns `SUCCESS`. The second user's execution reads stock = 0, fails the conditional check, and returns `SOLD_OUT`.

---

### Question 5: "How do you prove inventory never becomes negative?"
**Answer**: The Lua script checks `if current_stock >= requested_quantity` before executing `DECRBY`. Because Redis executes scripts without preemption, $S_k \ge 0$ is a mathematically guaranteed invariant.

---

### Question 6: "What happens if Redis fails?"
**Answer**: Redis replication is asynchronous. During uncertain Redis failover, SALESTORM **fails closed** (returns HTTP 503 retryable responses) until Redis memory state is reconciled against persistent PostgreSQL reservation records.

---

### Question 7: "What happens if Redis reservation succeeds but PostgreSQL persistence fails?"
**Answer**: The reservation exists in Redis with a 10-minute TTL trigger key. If no matching PostgreSQL record or payment arrives within 10 minutes, the Expiration Sweeper detects missing SQL state and executes an atomic Lua stock restoration (`INCRBY`).

---

### Question 8: "What happens if the same Buy request is sent twice?"
**Answer**: The API Gateway checks the `Idempotency-Key` header. Redis fast lock catches the duplicate in <1.5ms. PostgreSQL enforces `UNIQUE(idempotency_key)` to ensure duplicate requests never create multiple reservations.

---

### Question 9: "What happens if the same payment request is sent twice?"
**Answer**: Payment Service uses a unique transaction ID (`payment_id = PAY-<reservation_id>`) passed to payment providers. Payment gateway tokenization and PostgreSQL unique indices ensure a payment is charged only once.

---

### Question 10: "What happens if reservation expires exactly when payment succeeds?"
**Answer**: Only a valid, unexpired reservation can transition to `CONFIRMED`. If the reservation was already marked `RELEASED` by the sweeper, payment confirmation fails, and an automated refund/compensation process is triggered.

---

### Question 11: "What happens if Payment succeeds and Order Service is down?"
**Answer**: Payment Service writes payment status (`CONFIRMED`) and a `salestorm.payment.completed` event into local PostgreSQL `outbox_events` in one local ACID transaction. Kafka retains the message. When Order Service recovers after 30s, its idempotent consumer creates the order. Data loss = 0%.

---

### Question 12: "Why use Kafka?"
**Answer**: Kafka provides durable, asynchronous, append-only message streaming. It decouples Payment Service from Order Service, ensuring temporary Order Service outages do not block user payment completion.

---

### Question 13: "Why use Transactional Outbox?"
**Answer**: It eliminates the dual-write problem between database updates and message publishing. Writing business state and outbox events in a single local SQL transaction guarantees At-Least-Once event delivery.

---

### Question 14: "What happens if Kafka delivers the same message twice?"
**Answer**: Order Service implements an idempotent consumer. It attempts SQL `INSERT INTO orders (reservation_id...)`. The `UNIQUE(reservation_id)` constraint triggers `ON CONFLICT DO NOTHING`, executing safely without duplicate orders.

---

### Question 15: "Why don't you hold a DB transaction open during payment?"
**Answer**: Holding database transactions open during third-party HTTP payment calls (which take 1-3 seconds) exhausts database connection pools almost instantly, leading to system-wide failure.

---

### Question 16: "How do you handle 500,000 incoming requests/sec?"
**Answer**: Layered admission control: Cloudflare WAF drops bot traffic $\rightarrow$ API Gateway Token Bucket rate limits per user $\rightarrow$ Virtual Waiting Room queue admits controlled batches based on downstream capacity.

---

### Question 17: "What protects the database?"
**Answer**: 
1. Redis atomic fast-path sheds 9,900 unsuccessful requests in-memory.
2. Virtual Waiting Room caps active concurrent checkouts.
3. PgBouncer connection poolers multiplex 6,000 application threads down to 250 DB connections.

---

### Question 18: "What is the hot-product problem?"
**Answer**: When 10,000 users target Product X, all requests hit a single database row or Redis key. SALESTORM handles this by using Redis hash tags (`{product_1001}`) on dedicated cluster shards and offloading catalog read queries to 16 read replicas.

---

### Question 19: "What is the main bottleneck?"
**Answer**: The single-threaded Redis cluster shard handling the hot product key. Redis processes ~85,000 ops/sec per shard, which comfortably handles the 10,000 concurrent user fast-path filter.

---

### Question 20: "What are the biggest trade-offs?"
**Answer**: 
1. Redis fast-path and PostgreSQL durable store have a non-atomic dual-write boundary (mitigated via sweepers).
2. Asynchronous Redis replication forces a fail-closed policy during failover.
3. Downstream order creation is eventually consistent.
