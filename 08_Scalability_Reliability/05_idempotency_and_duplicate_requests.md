# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 05: Idempotency Architecture — Purchase & Payment Deduplication

---

### 1. Separation of Idempotency Concerns

During flash sales, aggressive client retries produce an estimated **2% duplicate request flood** (200 duplicate requests out of 10,000). SALESTORM explicitly separates Purchase Idempotency from Payment Idempotency:

```
[ Incoming Client Request ]
             |
             +---> Purchase Idempotency (`Idempotency-Key: BUY-usr1-prod1001-001`)
             |     - Redis Fast Filter (<1.5ms)
             |     - PostgreSQL Durable `UNIQUE(idempotency_key)` Constraint
             |
             +---> Payment Idempotency (`payment_id: PAY-res9981-001`)
                   - Unique Transaction Reference
                   - Gateway Provider Tokenization
```

---

### 2. Purchase Idempotency Protocol

Every `POST /api/v1/reservations` request mandates header `Idempotency-Key: BUY-<user>-<product>-<nonce>`.

1. **Redis Fast Filter**:
   - API Gateway executes `SET idempotency:<key> IN_PROGRESS NX EX 10`.
   - If key exists and status is `COMPLETED`, returns cached HTTP 201 response in <1.5ms.
   - If key exists and status is `IN_PROGRESS`, returns HTTP 409 Conflict ("Request in-flight").
2. **Durable Database Safety**:
   - PostgreSQL enforces `UNIQUE(idempotency_key)` on table `reservations`.
   - Ensures duplicate requests never create multiple reservations even if Redis keys expire or fail over.

---

### 3. Payment Idempotency Protocol

Every `POST /api/v1/payments` request uses a unique transaction reference `payment_id = PAY-<reservation_id>-<nonce>`.

- Passed directly to third-party payment gateways (Stripe / Adyen idempotency token).
- Prevents double-charging user credit cards during payment network retries.
