# 6. Event payloads: Payment, Order and Inventory

## Envelope and delivery
All events are JSON, UTF-8, UTC timestamps, schema_version=1. event_id remains unchanged on relay retries. aggregate_version is a monotonic local aggregate transition version, not a global sequence. Broker partition/routing key is aggregate_id. Consumers still guard state because events can be duplicated, delayed or arrive out of order across topics. Examples below are separate scenarios, not one chronological purchase.

| Event | Producer | Consumers | Topic |
|---|---|---|---|
| CheckoutCompleted | Checkout | Order | checkout.events |
| PaymentFailed | Payment | Inventory, Checkout | payment.events |
| OrderConfirmed | Order | Fulfilment, Notification | order.events |
| ReservationExpired | Inventory | Checkout | inventory.events |
| ReservationReleased | Inventory | Checkout | inventory.events |
| ShipmentUpdated | Fulfilment | Order, Notification | shipment.events |

## CheckoutCompleted
Producer: Checkout. Consumers: Order. Topic: `checkout.events`.
```json
{
  "event_id": "55555555-5555-4555-8555-000000000001",
  "schema_version": 1,
  "occurred_at": "2026-10-05T06:40:12Z",
  "correlation_id": "11111111-1111-4111-8111-111111111111",
  "aggregate_id": "11111111-1111-4111-8111-111111111111",
  "aggregate_version": 1,
  "event_type": "CheckoutCompleted",
  "data": {
    "checkout_id": "11111111-1111-4111-8111-111111111111",
    "customer_id": "demo-customer-001",
    "reservation_id": "22222222-2222-4222-8222-222222222222",
    "reservation_status": "COMMITTED",
    "payment_id": "33333333-3333-4333-8333-333333333333",
    "payment_status": "CAPTURED",
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
}
```

## PaymentFailed
Producer: Payment. Consumers: Inventory, Checkout. Topic: `payment.events`.
```json
{
  "event_id": "55555555-5555-4555-8555-000000000002",
  "schema_version": 1,
  "occurred_at": "2026-10-05T06:40:12Z",
  "correlation_id": "11111111-1111-4111-8111-111111111111",
  "aggregate_id": "33333333-3333-4333-8333-333333333333",
  "aggregate_version": 1,
  "event_type": "PaymentFailed",
  "data": {
    "payment_id": "33333333-3333-4333-8333-333333333333",
    "checkout_id": "11111111-1111-4111-8111-111111111111",
    "reservation_id": "22222222-2222-4222-8222-222222222222",
    "status": "DECLINED",
    "reason": "INSUFFICIENT_FUNDS",
    "definitive": true
  }
}
```

## OrderConfirmed
Producer: Order. Consumers: Fulfilment, Notification. Topic: `order.events`.
```json
{
  "event_id": "55555555-5555-4555-8555-000000000003",
  "schema_version": 1,
  "occurred_at": "2026-10-05T06:40:12Z",
  "correlation_id": "11111111-1111-4111-8111-111111111111",
  "aggregate_id": "44444444-4444-4444-8444-444444444444",
  "aggregate_version": 1,
  "event_type": "OrderConfirmed",
  "data": {
    "order_id": "44444444-4444-4444-8444-444444444444",
    "checkout_id": "11111111-1111-4111-8111-111111111111",
    "customer_id": "demo-customer-001",
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
}
```

## ReservationExpired
Producer: Inventory. Consumers: Checkout. Topic: `inventory.events`.
```json
{
  "event_id": "55555555-5555-4555-8555-000000000004",
  "schema_version": 1,
  "occurred_at": "2026-10-05T06:45:05Z",
  "correlation_id": "11111111-1111-4111-8111-111111111111",
  "aggregate_id": "22222222-2222-4222-8222-222222222222",
  "aggregate_version": 1,
  "event_type": "ReservationExpired",
  "data": {
    "reservation_id": "22222222-2222-4222-8222-222222222222",
    "checkout_id": "11111111-1111-4111-8111-111111111111",
    "sku": "FLASH-001",
    "quantity": 1,
    "status": "EXPIRED",
    "expires_at": "2026-10-05T06:45:00Z"
  }
}
```

## ReservationReleased
Producer: Inventory. Consumers: Checkout. Topic: `inventory.events`.
```json
{
  "event_id": "55555555-5555-4555-8555-000000000005",
  "schema_version": 1,
  "occurred_at": "2026-10-05T06:40:12Z",
  "correlation_id": "11111111-1111-4111-8111-111111111111",
  "aggregate_id": "22222222-2222-4222-8222-222222222222",
  "aggregate_version": 1,
  "event_type": "ReservationReleased",
  "data": {
    "reservation_id": "22222222-2222-4222-8222-222222222222",
    "checkout_id": "11111111-1111-4111-8111-111111111111",
    "sku": "FLASH-001",
    "quantity": 1,
    "status": "RELEASED",
    "reason": "PAYMENT_DECLINED"
  }
}
```

## ShipmentUpdated
Producer: Fulfilment. Consumers: Order, Notification. Topic: `shipment.events`.
```json
{
  "event_id": "55555555-5555-4555-8555-000000000006",
  "schema_version": 1,
  "occurred_at": "2026-10-05T06:40:12Z",
  "correlation_id": "11111111-1111-4111-8111-111111111111",
  "aggregate_id": "77777777-7777-4777-8777-777777777777",
  "aggregate_version": 1,
  "event_type": "ShipmentUpdated",
  "data": {
    "shipment_id": "77777777-7777-4777-8777-777777777777",
    "order_id": "44444444-4444-4444-8444-444444444444",
    "status": "OUT_FOR_DELIVERY",
    "carrier": "MockCarrier",
    "tracking_number": "MOCK001"
  }
}
```

## Consumer effects and guards
- CheckoutCompleted: create one order per checkout only when payload indicates CAPTURED and COMMITTED. Checkout is the trusted producer and must verify these through owner APIs before publication. Keep item prices/address snapshots so Order does not depend on current catalogue values. Restrict access to events containing delivery data.
- PaymentFailed: Inventory releases only HELD reservations associated with the same checkout/payment workflow. A stale event cannot release COMMITTED. Checkout treats it as definitive failure only if its own workflow has not advanced to a conflicting terminal state.
- ReservationExpired/Released: Checkout reconciles Payment. If payment is captured but the reservation is terminally released, request a refund; do not create an order. If payment is unknown continue reconciliation.
- OrderConfirmed: Fulfilment creates one shipment operation per order; Notification deduplicates event/channel. Publish only from the Order transaction outbox.
- ShipmentUpdated: validate legal order/shipment transitions and reject stale versions. This supporting event makes delivery tracking explicit.

## Success discovery and additional events
A PaymentSucceeded event is not required by the supplied HLD: Checkout discovers CAPTURED through the synchronous response or Payment status API/reconciliation. Do not introduce a second independent order-creation trigger. If the team later adds PaymentSucceeded, Checkout alone consumes it as a wake-up signal and still commits inventory first.

## Versioning and replay
Schema files are strict version-1 contracts. A changed payload shape requires an explicit compatibility review; breaking changes require a new schema_version and consumers supporting both during migration. Quarantine unknown versions instead of interpreting them incorrectly. Replays preserve event IDs; a corrected business fact uses a new event/version and audit trail. Outbox payload stores the data body and columns provide envelope metadata; the relay builds the complete envelope.
