# 4. REST API specification
REST/JSON is selected for this proposed contract; gRPC is not additionally required. If the team selects gRPC later, map the same message schemas and semantics rather than maintaining inconsistent alternatives. openapi.yaml is the machine-readable definition.

## Common protocol rules
HTTPS outside localhost. Customer JWT subject determines customer_id; enforce resource ownership on every customer lookup. Service tokens have scoped permissions; public customers cannot reserve/commit/refund directly. X-Correlation-ID follows checkout across services. All mutation retries preserve Idempotency-Key and the canonical request body. Prices, totals, customer identity and TTL are server-derived, never trusted from browser input. Do not log or persist raw payment tokens in idempotency bodies.
POST checkout/payment/refund uses 202 for an accepted workflow; GET returns its current state. A transport success does not mean payment succeeded. 409 means a state/business conflict; 429 may retry with backoff; 503 is an infrastructure result. Check structured resource states. For pending 3DS return next_action_url, then polling/reconciliation resumes; HTTP connections do not stay open while the customer enters OTP.

| Method | Path | Caller | Response |
|---|---|---|---|
| POST | `/api/v1/checkout` | CustomerBearer | 202 Checkout |
| GET | `/api/v1/checkout/{checkout_id}` | CustomerBearer | 200 Checkout |
| POST | `/v1/inventory/reservations` | ServiceBearer | 201 Reservation |
| GET | `/v1/inventory/reservations/{reservation_id}` | ServiceBearer | 200 Reservation |
| POST | `/v1/inventory/reservations/{reservation_id}/commit` | ServiceBearer | 200 Reservation |
| POST | `/v1/inventory/reservations/{reservation_id}/release` | ServiceBearer | 200 Reservation |
| POST | `/v1/payments` | ServiceBearer | 202 Payment |
| GET | `/v1/payments/status` | ServiceBearer | 200 Payment |
| POST | `/v1/payments/{payment_id}/refunds` | ServiceBearer | 202 Refund |
| GET | `/v1/payments/{payment_id}/refunds` | ServiceBearer | 200 Refund |
| POST | `/v1/payments/webhooks` | WebhookSignature | 200 Ack |
| GET | `/api/v1/orders/{order_id}` | CustomerBearer | 200 Order |
| GET | `/api/v1/products` | CustomerBearer | 200 ProductList |
| GET | `/api/v1/products/{sku}` | CustomerBearer | 200 Product |
| GET | `/api/v1/cart` | CustomerBearer | 200 Cart |
| POST | `/api/v1/cart/items` | CustomerBearer | 200 Cart |
| GET | `/api/v1/orders/{order_id}/tracking` | CustomerBearer | 200 Tracking |

### POST /api/v1/checkout
Accepted checkout; poll status. SUCCESS still allows order creation pending. Customer identity and prices are derived server-side.
Request example:
```json
{
  "items": [
    {
      "sku": "FLASH-001",
      "quantity": 1
    }
  ],
  "payment_token": "mock_token_success",
  "delivery_address": {
    "street": "12 Example Street",
    "city": "Coimbatore",
    "state": "Tamil Nadu",
    "postal_code": "641001",
    "country": "IN"
  }
}
```
Response example:
```json
{
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "status": "SUCCESS",
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "payment_id": "33333333-3333-4333-8333-333333333333",
  "amount_minor": 99900,
  "currency": "INR"
}
```

### GET /api/v1/checkout/{checkout_id}
Retrieve own checkout and current progress; order_id appears when known.
Response example:
```json
{
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "status": "SUCCESS",
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "payment_id": "33333333-3333-4333-8333-333333333333",
  "amount_minor": 99900,
  "currency": "INR"
}
```

### POST /v1/inventory/reservations
Checkout only: reserve one unit for 300 seconds; no client-controlled TTL.
Request example:
```json
{
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "sku": "FLASH-001",
  "quantity": 1
}
```
Response example:
```json
{
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "sku": "FLASH-001",
  "quantity": 1,
  "status": "HELD",
  "expires_at": "2026-10-05T06:45:00Z"
}
```

### GET /v1/inventory/reservations/{reservation_id}
Checkout/recovery only: authoritative reservation status.
Response example:
```json
{
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "sku": "FLASH-001",
  "quantity": 1,
  "status": "HELD",
  "expires_at": "2026-10-05T06:45:00Z"
}
```

### POST /v1/inventory/reservations/{reservation_id}/commit
Checkout only: verified captured payment, matching checkout, active hold; returns COMMITTED. Idempotent replay succeeds for same bound payment.
Request example:
```json
{
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "payment_id": "33333333-3333-4333-8333-333333333333"
}
```
Response example:
```json
{
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "sku": "FLASH-001",
  "quantity": 1,
  "status": "COMMITTED",
  "expires_at": "2026-10-05T06:45:00Z",
  "payment_id": "33333333-3333-4333-8333-333333333333"
}
```

### POST /v1/inventory/reservations/{reservation_id}/release
Checkout only: releases HELD once. COMMITTED returns 409. Terminal RELEASED/EXPIRED is a safe no-op.
Request example:
```json
{
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "reason": "PAYMENT_DECLINED"
}
```
Response example:
```json
{
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "sku": "FLASH-001",
  "quantity": 1,
  "status": "RELEASED",
  "expires_at": "2026-10-05T06:45:00Z"
}
```

### POST /v1/payments
Checkout only: create/reuse durable payment intent. CAPTURED, PENDING_3DS, UNKNOWN or definitive failure is represented in the resource status.
Request example:
```json
{
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "amount_minor": 99900,
  "currency": "INR",
  "payment_token": "mock_token_success"
}
```
Response example:
```json
{
  "payment_id": "33333333-3333-4333-8333-333333333333",
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "status": "CAPTURED",
  "amount_minor": 99900,
  "currency": "INR",
  "provider_reference": "mock_charge_001"
}
```

### GET /v1/payments/status
Checkout recovery only: look up payment by checkout_id; a missing record is not proof that no provider operation exists.
Response example:
```json
{
  "payment_id": "33333333-3333-4333-8333-333333333333",
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "status": "CAPTURED",
  "amount_minor": 99900,
  "currency": "INR",
  "provider_reference": "mock_charge_001"
}
```

### POST /v1/payments/{payment_id}/refunds
Checkout recovery only: one full refund; amount comes from captured payment. Requires definitive reservation rejection; no refund on ambiguous commit.
Request example:
```json
{
  "reason": "RESERVATION_EXPIRED"
}
```
Response example:
```json
{
  "refund_id": "66666666-6666-4666-8666-666666666666",
  "payment_id": "33333333-3333-4333-8333-333333333333",
  "status": "PENDING",
  "amount_minor": 99900
}
```

### GET /v1/payments/{payment_id}/refunds
Retrieve full-refund progress; refund success requires provider confirmation.
Response example:
```json
{
  "refund_id": "66666666-6666-4666-8666-666666666666",
  "payment_id": "33333333-3333-4333-8333-333333333333",
  "status": "PENDING",
  "amount_minor": 99900
}
```

### POST /v1/payments/webhooks
Normalized mock-provider contract. Verify signature/timestamp and durably process or enqueue before acknowledging. Real providers require adapter mapping.
Request example:
```json
{
  "provider_event_id": "mock_evt_001",
  "payment_id": "33333333-3333-4333-8333-333333333333",
  "provider_reference": "mock_charge_001",
  "status": "CAPTURED",
  "occurred_at": "2026-10-05T06:40:10Z"
}
```
Response example:
```json
{
  "accepted": true
}
```

### GET /api/v1/orders/{order_id}
Retrieve own order; creation is event-only, with no customer POST /orders.
Response example:
```json
{
  "order_id": "44444444-4444-4444-8444-444444444444",
  "checkout_id": "11111111-1111-4111-8111-111111111111",
  "customer_id": "demo-customer-001",
  "reservation_id": "22222222-2222-4222-8222-222222222222",
  "payment_id": "33333333-3333-4333-8333-333333333333",
  "status": "CONFIRMED",
  "items": [
    {
      "sku": "FLASH-001",
      "quantity": 1,
      "unit_price_minor": 99900
    }
  ],
  "amount_minor": 99900,
  "currency": "INR",
  "delivery_address": {
    "street": "12 Example Street",
    "city": "Coimbatore",
    "state": "Tamil Nadu",
    "postal_code": "641001",
    "country": "IN"
  }
}
```

### GET /api/v1/products
List catalogue; stock hint is advisory.
Response example:
```json
{
  "items": [
    {
      "sku": "FLASH-001",
      "name": "Flash-sale product",
      "unit_price_minor": 99900,
      "currency": "INR",
      "availability_hint": "LIMITED"
    }
  ]
}
```

### GET /api/v1/products/{sku}
Read current catalogue price; checkout validates its own authoritative price snapshot.
Response example:
```json
{
  "sku": "FLASH-001",
  "name": "Flash-sale product",
  "unit_price_minor": 99900,
  "currency": "INR",
  "availability_hint": "LIMITED"
}
```

### GET /api/v1/cart
Read own ephemeral cart; cart never holds inventory.
Response example:
```json
{
  "items": [
    {
      "sku": "FLASH-001",
      "quantity": 1
    }
  ],
  "version": 1
}
```

### POST /api/v1/cart/items
Set one cart SKU quantity to one (not increment); operation is naturally idempotent. Key mismatch detection is retained with cart metadata.
Request example:
```json
{
  "sku": "FLASH-001",
  "quantity": 1
}
```
Response example:
```json
{
  "items": [
    {
      "sku": "FLASH-001",
      "quantity": 1
    }
  ],
  "version": 1
}
```

### GET /api/v1/orders/{order_id}/tracking
Read own tracking state; PENDING until shipment is created.
Response example:
```json
{
  "order_id": "44444444-4444-4444-8444-444444444444",
  "status": "PENDING"
}
```

## Error codes
OUT_OF_STOCK, RESERVATION_EXPIRED, RESERVATION_RELEASED, RESERVATION_ALREADY_COMMITTED, IDEMPOTENCY_KEY_REUSED, INVALID_TRANSITION, NOT_FOUND, NOT_AUTHORIZED, RATE_LIMITED, DEPENDENCY_UNAVAILABLE. Transport failures must not be translated into PAYMENT_FAILED.
```json
{
  "code": "OUT_OF_STOCK",
  "message": "No unit available for reservation.",
  "correlation_id": "11111111-1111-4111-8111-111111111111",
  "retryable": false
}
```

## Customer cancellation and returns
Post-confirmation cancellation/RMA APIs are outside this demo contract. Order states retain CANCELLED/REFUNDED for the broader LLD. A future cancellation saga must coordinate refund, shipment interception and audited restocking; the reservation release endpoint cannot undo a committed sale.
