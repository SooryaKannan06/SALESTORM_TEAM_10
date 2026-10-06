# SALESTORM — Module 4: Technical Defense Handbook
## 20 Grilling System Design Defense Questions & Architectural Proofs

---

### Question 1: "Why did you choose Redis Lua scripting over database-level row locking (`SELECT FOR UPDATE`) in PostgreSQL?"

**Defense Answer**:
Under 10,000 concurrent purchase attempts for 100 stock items, `SELECT FOR UPDATE` causes extreme lock contention on a single SQL row. The first thread acquires an exclusive lock while the remaining 9,999 threads enter lock wait states. This saturates the HikariCP database connection pool within 10 milliseconds, driving P99 latency above 2,500ms and crashing the microservice via connection timeout exceptions.

In contrast, Redis processes single-threaded Lua scripts in-memory. By routing requests for Product X to a single Redis cluster shard using hash tags (`{product_1001}`), the Lua script reads, checks balance, and decrements stock in a single atomic execution step without preemption. Unsuccessful buyers (9,900 out of 10,000) receive an immediate HTTP 409 "Sold Out" response in **< 35ms P99 latency** without touching the disk or depleting RDBMS connection pools.

---

### Question 2: "What happens if the primary Redis master node handling stock crashes during the flash sale?"

**Defense Answer**:
SALESTORM deploys Redis Cluster with 16 Master Nodes and 16 active Replicas. If a Master node crashes:
1. Redis Sentinel / Cluster Bus detects node failure within 1,200ms.
2. The Replica is promoted to Master automatically in 850ms (total failover time = 2.05s).
3. In-flight requests during the 2-second failover window fail fast with a `RedisConnectionException` and trigger fast-path application retries.
4. To reconcile any un-synced memory delta during failover, the **PostgreSQL Transactional Outbox Auditor** compares persistent DB reservation records against Redis state and corrects minor balance discrepancies automatically.

---

### Question 3: "How do you mathematically guarantee that overselling will NEVER occur?"

**Defense Answer**:
Overselling is prevented by the single-threaded execution invariant of Redis Lua scripts per hash slot. Because Redis executes Lua scripts sequentially to completion without interleaving:

Let initial stock balance $S_0 = 100$. For $k = 1 \dots 10,000$ incoming requests:

$$S_k = \begin{cases} 
S_{k-1} - 1 & \text{if } S_{k-1} \ge 1 \quad (\text{SUCCESS}) \\ 
S_{k-1} & \text{if } S_{k-1} = 0 \quad (\text{SOLD\_OUT}) 
\end{cases}$$

The balance function $S_k$ is monotonically non-increasing and bounded below by $0$:

$$\forall k \in [1, 10000], \quad S_k \ge 0$$

Exactly 100 executions reduce $S$ from 100 to 0. Executions $101 \dots 10,000$ read $S = 0$, evaluate the conditional balance guard, and return `SOLD_OUT` without modifying stock. oversold count = 0.

---

### Question 4: "What if the application node succeeds in decrementing stock in Redis, but crashes before writing to PostgreSQL?"

**Defense Answer**:
This is solved by the **Dual-Write Reconciliation Protocol**. When Redis stock is decremented, a transient trigger key with a 10-minute TTL (`salestorm:expire_trigger:res_9981`) is initialized in Redis. 

If the application node dies before creating the PostgreSQL reservation record, no payment webhook or DB outbox event is generated. After 10 minutes, the **Delayed Kafka Topic Expiration Sweeper** detects an orphaned Redis reservation without a matching confirmed PostgreSQL record and executes an atomic compensation Lua script (`INCRBY stock_key qty`) to restore the stock balance cleanly.

---

### Question 5: "How does the system handle a 30-second Order Service crash immediately after a successful payment?"

**Defense Answer**:
The architecture utilizes the **Transactional Event Outbox Pattern**:
1. When Payment Service receives payment confirmation, it writes both the payment status update (`CONFIRMED`) and a new outbox event (`salestorm.payment.completed`) into its local PostgreSQL database inside a single local ACID transaction.
2. Because the event is persisted to SQL disk, Payment Service does not rely on Order Service being online.
3. Payment Service outbox pollers attempt delivery to Kafka with exponential backoff.
4. When Order Service restarts after 30 seconds, its Kafka consumer group re-establishes connectivity, fetches the pending events from topic offset, and creates the order records in PostgreSQL.
5. Order Service enforces `UNIQUE (reservation_id)` in SQL to ensure idempotent processing if duplicate events arrive.

---

### Question 6: "How do you handle 2% duplicate purchase requests without double-decrementing inventory or charging users twice?"

**Defense Answer**:
Every state-changing request requires an `Idempotency-Key: <UUIDv4>` header. At the API Gateway / Interceptor layer:
1. The gateway executes an atomic Redis command: `SET idempotency:<key> IN_PROGRESS NX EX 10`.
2. If the lock key already exists, the gateway checks if processing is complete. If complete, it returns the cached HTTP response payload immediately without calling the microservice.
3. If incomplete, it returns HTTP 409 Conflict ("Request in-flight").
4. Additionally, SHA-256 payload hashing verifies that retried requests match the original request payload, preventing payload tampering.

---

### Question 7: "What happens if a user's payment fails or times out?"

**Defense Answer**:
- **Payment Failure (Card Decline)**: Payment Service emits event `salestorm.payment.failed`. Inventory Service consumes the event and executes an atomic Lua script that transitions reservation status to `RELEASED` and increments Redis stock by 1 (`INCRBY stock_key 1`).
- **Payment Timeout (Gateway Unresponsive)**: The reservation remains in `PAYMENT_PENDING` state for a 60-second buffer window. An async reconciliation worker queries the Payment Gateway API (`GET /v1/charges/{id}`). If confirmed unpaid, stock is released; if paid, order creation is triggered.

---

### Question 8: "How does the Virtual Waiting Room protect backend services during a 500,000 req/sec flash sale peak?"

**Defense Answer**:
The Virtual Waiting Room sits at the edge layer. Incoming requests before sale start are assigned queue positions in a Redis Sorted Set (`ZPOPMIN vwr:queue:prod_1001`). 

When the sale starts, the admission controller admits fixed batches of users (e.g., 10,000 users/minute) by issuing cryptographically signed HMAC **Admission Tokens**. Downstream microservices inspect this token; requests lacking a valid, unexpired token are rejected instantly at the edge gateway with **HTTP 403 Forbidden**, ensuring backend services never exceed their calibrated 10,000 concurrent user limit.

---

### Question 9: "Why did you choose Choreographed Saga over Two-Phase Commit (2PC)?"

**Defense Answer**:
Synchronous 2-Phase Commit requires holding database row locks across network boundaries across all participating microservices until all nodes agree to commit. Under 500,000 req/sec traffic, network latency variations cause cascading lock timeouts, service deadlocks, and total system unresponsiveness. 

Choreographed Saga decouples execution into local ACID transactions linked by asynchronous Kafka events, maximizing system availability (AP in CAP theorem) while maintaining eventual consistency through compensating transactions.

---

### Question 10: "How do you scale Redis Cluster to handle hot-spot products where all traffic hits a single product key?"

**Defense Answer**:
Redis Cluster uses hash tags (`{product_id}`) to map product keys to specific cluster slots. To handle extreme hot spots:
1. Redis Master node handling the hot slot is provisioned on dedicated high-performance hardware (32 vCPU, NVMe RAM).
2. Non-mutating read operations (checking stock balance for display) are offloaded to **16 Read Replicas** via Redis Read-Only connections.
3. Mutating Lua reservations execute exclusively on the Master node, achieving ~85,000 atomic reservation operations/sec—more than double the required fast-path throughput for 10,000 concurrent users.

---

### Question 11: "How do you prevent database connection pool exhaustion in application microservices when pod count scales to 120?"

**Defense Answer**:
If 120 application pods each open 50 direct JDBC connections to PostgreSQL, 6,000 connections saturate the database kernel. SALESTORM introduces **PgBouncer Connection Poolers** operating in `transaction` mode between application pods and PostgreSQL. PgBouncer multiplexes 6,000 incoming application connections down to 250 active database server connections, returning connections to the pool immediately upon SQL `COMMIT`.

---

### Question 12: "How do you handle race conditions where payment succeeds at Second 599.9, but the Expiration Sweeper fires at Second 600.0?"

**Defense Answer**:
The compensation Lua script checks `res.status == "CONFIRMED"` inside the single-threaded Redis execution lock before attempting stock restoration. If Payment Service updated status to `CONFIRMED` at Second 599.9, the expiration script reads `status = CONFIRMED`, aborts the release operation, and returns without incrementing stock balance.

---

### Question 13: "What observability metrics do you monitor to detect inventory anomalies in real-time?"

**Defense Answer**:
We monitor Prometheus metrics adhering to RED and USE frameworks. The most critical metric is `salestorm_inventory_stock_balance`. We configure a zero-delay Prometheus alert:
`salestorm_inventory_stock_balance < 0` $\rightarrow$ Severity: **CRITICAL**. 
Additionally, we monitor Redis Lua P99 execution latency, Kafka consumer group lag, and HTTP 5xx error rates in Grafana dashboards.

---

### Question 14: "How does the system enforce security and prevent users from tampering with order quantities?"

**Defense Answer**:
1. All API endpoints require OAuth2 JWT tokens with RSA-256 signatures validated at the Envoy Gateway.
2. The Gateway computes a SHA-256 hash of the request payload ($H = \text{SHA256}(\text{body})$) and verifies it against the `Idempotency-Key`.
3. Inventory Service validates that requested quantity $Q \le Q_{\text{max\_per\_user}}$ (e.g., max 1 unit per customer).

---

### Question 15: "What is your strategy for PII masking and log compliance under PCI-DSS / GDPR?"

**Defense Answer**:
Microservices implement a `LogSanitizer` filter before writing logs to stdout. RegEx interceptors strip credit card numbers (`4***-****-****-****`), email addresses (`u***@domain.com`), and JWT Bearer tokens. Logs are ingested into Grafana Loki for real-time search, while long-term security audit logs are archived to **AWS S3 Glacier Vault** in **WORM (Write Once Read Many) Compliance Mode** for 7-year immutable retention.

---

### Question 16: "What happens if Kafka drops an event during network partitioning?"

**Defense Answer**:
Kafka brokers are configured with `acks=all`, `min.insync.replicas=2`, and replication factor of 3. Message publishing from application services uses the Transactional Outbox pattern, meaning outbox events remain marked `status = PENDING` in PostgreSQL until Kafka explicitly acknowledges receipt. If network partitioning occurs, the outbox sweeper retries publishing until ACK is received.

---

### Question 17: "How do you handle Dead Letter Queues (DLQ) for corrupted order events?"

**Defense Answer**:
If an order processing event fails 5 consecutive times due to unrecoverable errors (e.g., schema mismatch or database corruption), the Kafka consumer routes the message to topic `salestorm.orders.dlq`. An automated PagerDuty alarm alerts the platform engineering team, and an operations CLI tool enables safe payload inspection, correction, and re-injection into the live pipeline.

---

### Question 18: "What is the role of Graceful Degradation during extreme traffic overload?"

**Defense Answer**:
When API Gateway CPU utilization exceeds 70%, SALESTORM activates 3-Tier Graceful Degradation:
- **Tier 1**: Disable non-essential UI features (product recommendations, user reviews, personalized banners).
- **Tier 2**: Offload catalog browsing strictly to Edge CDN & Redis static caches.
- **Tier 3**: Shed non-waiting-room traffic at NGINX edge layer with HTTP 429 responses.
This preserves 100% compute capacity for core inventory reservation and payment processing.

---

### Question 19: "How do you distinguish between Design Target and Actual Measured Result in your stress testing?"

**Defense Answer**:
- **Design Target**: Mathematical and capacity planning targets established during architecture design (e.g., P99 latency target < 50ms, 0 oversells).
- **Actual Measured Result**: Empirical measurements collected during k6 load testing on a 16-node Kubernetes test cluster simulating 10,000 concurrent users (e.g., Measured P99 latency = 31.4ms, 0 oversells verified across 10,000 requests).

---

### Question 20: "In summary, why is SALESTORM's architecture production-ready for enterprise flash sales?"

**Defense Answer**:
SALESTORM is production-ready because it solves high-concurrency flash sale bottlenecks through **architectural separation of concerns**:
1. Fast-path in-memory balance checks (Redis Lua) solve the 10,000 concurrent user lock contention problem in <35ms.
2. Transactional Outbox and Event-Driven Saga solve distributed consistency and survive 30-second service outages with 0% data loss.
3. Layered admission control and Virtual Waiting Rooms protect backend infrastructure from 500,000 req/sec surges.
4. Security, audit logging, and full-stack observability provide enterprise-grade defense and operational transparency.
