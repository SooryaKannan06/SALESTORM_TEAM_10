# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 09: Backpressure, Traffic Shedding & Admission Control

---

### 1. The Need for Traffic Admission Control

During peak flash sales, incoming user request rate can spike instantaneously to **500,000 requests/sec**. Attempting to process all 500,000 requests through application logic when only 100 stock items exist leads to system collapse.

SALESTORM implements a **Layered Admission Control and Backpressure Pipeline**:

```
[ Incoming Flash Sale Surge: 500,000 req/sec ]
                      |
                      v
+-------------------------------------------------------+
| LAYER 1: Global Edge Protection (Cloudflare WAF)     | -> Drops DDoS / Bot traffic (150,000 req/s dropped)
+-------------------------------------------------------+
                      |  350,000 req/sec clean traffic
                      v
+-------------------------------------------------------+
| LAYER 2: API Gateway Token Bucket Rate Limiter       | -> Rate limits per IP / User (150,000 HTTP 429)
+-------------------------------------------------------+
                      |  200,000 req/sec authorized
                      v
+-------------------------------------------------------+
| LAYER 3: Virtual Waiting Room (Admission Queue)       | -> Admits batch of 10,000 active users/min
+-------------------------------------------------------+
                      |  10,000 concurrent purchase attempts
                      v
+-------------------------------------------------------+
| LAYER 4: Atomic Inventory Engine (Redis Lua)          | -> Exactly 100 Reservations granted
+-------------------------------------------------------+
```

---

### 2. Virtual Waiting Room (VWR) Architecture

The Virtual Waiting Room acts as a shock absorber. Users attempting to access the flash sale checkout before being admitted are assigned a queue position via a cryptographically signed ticket.

```
                  +-----------------------------------+
                  |   User Clicks "Enter Flash Sale"   |
                  +-----------------------------------+
                                    |
            Check Redis Sorted Set `vwr:queue:prod_1001`
                                    |
               +--------------------+--------------------+
               |                                         |
     [Slot Available]                         [Slot Full / Queue Active]
               |                                         |
               v                                         v
   Issue Admission JWT                       Assign Queue Position
   Redirect to Checkout Page                 Redirect to Waiting Room Screen
   (TTL = 5 minutes)                         (Live WebSocket Position Updates)
```

#### Queue Token Generation & Validation
When the admission worker opens a batch, top $K$ users from Redis Sorted Set (`ZPOPMIN vwr:queue:prod_1001 1000`) receive an encrypted **Admission Token**:

$$\text{Token} = \text{HMAC-SHA256}(\text{user\_id} \parallel \text{product\_id} \parallel \text{expire\_time}, \text{SecretKey})$$

The Inventory Service inspects the token header; requests lacking a valid, unexpired token are rejected immediately at the gateway with **HTTP 403 Forbidden**.

---

### 3. Rate Limiting Engine (Distributed Token Bucket)

API Gateway (Envoy Proxy) enforces per-IP and per-user token bucket rate limits:

```lua
-- Redis Rate Limiter Script (Token Bucket)
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local current = tonumber(redis.call('get', key) or "0")

if current + 1 > limit then
    return 0 -- Reject request (HTTP 429)
else
    redis.call("INCRBY", key, 1)
    if current == 0 then
        redis.call("EXPIRE", key, 1) -- 1-second sliding window
    end
    return 1 -- Allow request
end
```

- **Anonymous Users**: 10 requests / second per IP.
- **Authenticated Users**: 30 requests / second per User ID.
- **Excess Requests**: Return **HTTP 429 Too Many Requests** with `Retry-After: 2` header.

---

### 4. Graceful System Degradation Modes

When system load metrics cross critical thresholds, SALESTORM automatically engages **Graceful Degradation Tiers**:

```
[ Normal State ] ---> Load > 70% ---> [ Tier 1: Non-Critical Feature Shutdown ]
                                                     |
                                            Load > 85%
                                                     v
                                      [ Tier 2: Dynamic Cache Fallback ]
                                                     |
                                            Load > 95%
                                                     v
                                      [ Tier 3: Emergency Traffic Shedding ]
```

| Degradation Tier | Trigger Condition | System Actions | Impact on User Experience |
| :--- | :--- | :--- | :--- |
| **Tier 1: Non-Critical Shutdown** | CPU > 70% OR Gateway Latency > 300ms | Disable ML recommendation engine, personalized banners, user review widgets, address auto-complete. | Core checkout & inventory remain 100% operational; page render time decreases by 40%. |
| **Tier 2: Cache Fallback** | DB Connection Pool > 85% | Bypass DB queries for product details/catalog; serve strictly from Edge CDN & Redis static cache. | Instant product page loads; minor inventory display lag (actual stock checked on click). |
| **Tier 3: Emergency Shedding** | Gateway RPS > 450k OR Redis Memory > 90% | Reject all requests without valid Virtual Waiting Room tokens immediately at NGINX edge layer. | Flash sale buyers experience smooth checkout; late arrivals receive high-load waiting screen. |
