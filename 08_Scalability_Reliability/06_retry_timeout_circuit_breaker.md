# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 06: Fault Tolerance — Retries, Timeouts & Circuit Breakers

---

### 1. Inter-Service Reliability Principles

In a microservices flash sale platform executing 500,000 peak requests/sec, service degradation can cascade rapidly. A slow external Payment Gateway or a temporary delay in the Order Service must not cause resource exhaustion (thread starvation, memory leaks) across upstream services.

SALESTORM implements a **Defense-in-Depth Resiliency Layer** combining:
1. Strict Timeout Enforcements
2. Exponential Backoff with Full Jitter Retries
3. Sliding Window Circuit Breakers (Resilience4j / Envoy Mesh)
4. Graceful Fallback Mechanisms

---

### 2. Service Timeout Budget Hierarchy

To prevent holding HTTP client threads open indefinitely, every inter-service call enforces a strict, non-negotiable timeout budget:

```
[ User Client ] 
      |  Max Timeout = 3000ms
      v
[ API Gateway / Envoy ] 
      |  Max Timeout = 2500ms
      v
[ Inventory Service ] ------------+
      |  Max Timeout = 800ms      |  Max Timeout = 2000ms
      v                           v
[ PostgreSQL / Redis ]      [ Payment Service ] 
                                  |  Max Timeout = 1800ms
                                  v
                            [ External Payment Gateway ]
```

| Communication Path | Transport | Max Allowed Timeout | Retry Strategy | Circuit Breaker Action |
| :--- | :--- | :--- | :--- | :--- |
| **Client -> Gateway** | HTTPS / HTTP2 | 3,000 ms | No Retry (Client side) | Rate Limit (429) |
| **Gateway -> Inventory** | gRPC / REST | 800 ms | 1 Retry (Fast backoff) | Fallback to Sold Out |
| **Inventory -> Payment** | REST | 2,000 ms | 2 Retries with Jitter | Circuit Open -> Deferred Payment Queue |
| **Payment -> Gateway Ext** | HTTPS | 1,800 ms | 1 Retry (Idempotent) | Circuit Open -> Payment Fail |
| **Order Service -> DB** | JDBC | 500 ms | 2 Retries (Transient) | Connection pool alert |

---

### 3. Exponential Backoff with Full Jitter Formula

Retrying failed requests at static intervals (e.g., every 100ms) causes "thundering herd" spikes that re-insult a struggling service. SALESTORM mandates **Full Jitter Exponential Backoff**:

Given base backoff $t_{\text{base}} = 100\text{ms}$, maximum backoff $t_{\text{max}} = 1000\text{ms}$, and attempt number $n$:

$$t_{\text{temp}} = \min(t_{\text{max}}, t_{\text{base}} \times 2^n)$$

$$t_{\text{sleep}} = \text{random\_between}(0, t_{\text{temp}})$$

```java
// Java Implementation of Full Jitter Backoff
public class BackoffUtil {
    private static final long BASE_MS = 100;
    private static final long MAX_MS = 1000;
    private static final Random RANDOM = new Random();

    public static long calculateFullJitter(int attempt) {
        long temp = Math.min(MAX_MS, BASE_MS * (1L << attempt));
        return (long) (RANDOM.nextDouble() * temp);
    }
}
```

---

### 4. Circuit Breaker State Machine & Configuration

SALESTORM utilizes **Resilience4j** (application level) and **Envoy Proxy Outlier Detection** (mesh level).

```
                 +-----------------------------------+
                 |              CLOSED               |
                 |   (Normal Operation: 100% Traffic) |
                 +-----------------------------------+
                                   |
                  Failure Rate > 50% over 100 reqs
                  OR P99 Latency > 1500ms
                                   v
                 +-----------------------------------+
                 |               OPEN                |
                 | (Fast Fail: Rejects 100% Traffic) |
                 +-----------------------------------+
                                   |
                          Wait Duration = 10s
                                   v
                 +-----------------------------------+
                 |             HALF-OPEN             |
                 |  (Trial State: Allows 10% Traffic)|
                 +-----------------------------------+
                    /                             \
     Trial Succeeds (Failure < 10%)    Trial Fails (Failure >= 10%)
                  /                                 \
                 v                                   v
          [ Move to CLOSED ]                  [ Move to OPEN ]
```

#### Resilience4j Configuration Snippet
```yaml
resilience4j.circuitbreaker:
  instances:
    PaymentServiceBreaker:
      slidingWindowType: COUNT_BASED
      slidingWindowSize: 100
      minimumNumberOfCalls: 20
      failureRateThreshold: 50.0  # Open if 50% calls fail
      slowCallRateThreshold: 75.0 # Open if 75% calls take > 1500ms
      slowCallDurationThreshold: 1500ms
      waitDurationInOpenState: 10000ms
      permittedNumberOfCallsInHalfOpenState: 10
      automaticTransitionFromOpenToHalfOpenEnabled: true
```

---

### 5. Graceful Fallbacks under Circuit Opening

When the Payment Service circuit breaker trips to **OPEN**:
1. Upstream Inventory Service catches `CallNotPermittedException`.
2. Instead of returning 500 Internal Server Error, the system triggers the **Deferred Payment Fallback**.
3. Reservation state transitions to `PAYMENT_PENDING_DEFERRED`.
4. User receives: *"Your stock reservation is locked! Payment processing is experiencing high load. You have 15 minutes to complete payment via your dashboard."*
5. Upstream system health is protected from collapsing.
