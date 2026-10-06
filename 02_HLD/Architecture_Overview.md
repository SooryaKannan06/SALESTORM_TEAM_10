# SALESTORM: Architecture Overview & Request Flow

## 1. Macro-Level Request Flow (BUY NOW)
When a customer clicks "Buy Now" during the flash sale, the request travels through the following lifecycle:

1. **Client Request:** Customer initiates checkout.
2. **Edge:** Request hits CDN/WAF. Malicious traffic and bots are filtered.
3. **Gateway:** Load Balancer routes to API Gateway. Rate limiting and Auth validate the token from the IdP.
4. **Checkout Service (Orchestrator):** API Gateway routes to the Checkout Service.
5. **Inventory Check (Sync):** Checkout calls Inventory Service. Inventory Service attempts to reserve 1 unit. *If 0 left, return Out of Stock. If success, continue.*
6. **Payment Processing (Sync):** Checkout calls Payment Service. Payment Service safely calls Payment Gateway with an idempotency key.
7. **Success Response & Outbox:** If payment succeeds, Checkout Service persists the success state and a CheckoutCompleted event durably in its local Outbox. It returns "Payment successful; order creation pending" to the client immediately.
8. **Async Relay:** An outbox publisher reliably relays the CheckoutCompleted event to the Message Broker.
9. **Order Creation (Async):** Order Service consumes the event idempotently and writes the final order to the Order Database.
10. **Downstream (Async):** Order Service publishes OrderConfirmed. Fulfilment and Notification services consume this to arrange shipping and send emails.

---

## 2. Scalability Architecture
The architecture handles traffic in two distinct scopes: extreme edge traffic (~500,000 req/sec) and critical concurrency at checkout (~10,000 simultaneous purchase attempts).

- **Traffic Filtering (Edge):** Of the 500k req/sec flash-sale traffic, the vast majority are product views. The architecture targets a high cache-hit ratio for read-heavy catalogue traffic. CDN and application caching absorb the majority of repeated reads, shielding the backend.
- **Rate Limiting:** API Gateway enforces rate limits per user/IP to prevent abuse.
- **Horizontal Scaling:** API Gateways, Checkout Services, Sale Services, and Inventory Services autoscale based on CPU/Memory metrics (e.g., Kubernetes HPA).
- **Protecting the DB:** **Crucially, the 500,000 edge requests DO NOT reach the Inventory Database.** Traffic is filtered by the Gateway. Only legitimate, authenticated checkout attempts (the 10,000 critical concurrency requests) reach the Inventory Service. The Inventory Service handles this controlled contention using the concurrency-control mechanism defined by Member 4, guaranteeing that no more than the 100 available units can be successfully reserved.
- **Async Queueing:** Post-payment processing is queued in the Message Broker.

---

## 3. Architecture Bottlenecks & Mitigations

| Bottleneck | Why it Occurs | Architectural Mitigation |
|---|---|---|
| **Inventory Hot Key** | 10,000 users trying to update Product X's available_quantity simultaneously creates DB row lock contention. | **Inventory Service Boundary:** Funnels traffic. *The exact inventory concurrency mechanism (e.g., Optimistic locking vs Redis Lua scripts) is defined by Member 4.* |
| **Payment Gateway Throughput** | Third-party API cannot handle 10,000 concurrent sync requests. | **Checkout Orchestration:** Fails fast on inventory. Only a maximum of 100 requests (the available stock) will ever reach the Payment Gateway step. |
| **Order DB Write Spikes** | Sudden burst of confirmed orders attempting to write to the database. | **Message Broker:** Absorbs the spike. Order Service pulls messages at a sustainable throughput rate. |
| **Cache Hot Key** | Edge users requesting the same product JSON from Distributed Cache. | **Local Caching / CDN:** Use CDN at the edge, and in-memory caches inside the Product Service to reduce centralized cache hits. |

---

## 4. Architectural Trade-offs
- **Microservices vs Monolith:** Microservices chosen for independent scaling (Inventory must scale differently than Notification), despite increased deployment complexity.
- **Synchronous vs Asynchronous:** Payment and Inventory are synchronous for immediate consistency and user feedback, sacrificing some latency. Order processing is asynchronous for high resilience, sacrificing strong consistency (eventual consistency instead).
- **Service-Owned Data vs Single DB:** Each service owns its database schema to prevent schema coupling and cascading lock contention. No distributed 2PC transactions are used; resilience relies on Outbox and reconciliation.
- **Technology Neutrality:** Exact implementations of the Message Broker, Relational Databases, and Distributed Cache are deferred to Member 4's ADR.
