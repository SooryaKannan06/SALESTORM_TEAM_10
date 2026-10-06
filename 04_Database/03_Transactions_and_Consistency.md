# 3. Transaction boundaries and consistency models

## Purchase invariant
For fixed stock 100: available_stock + reserved_stock + sold_stock = 100. All quantities stay non-negative. Reservations in HELD sum to reserved_stock; COMMITTED reservations sum to sold_stock. At most one committed reservation and one order exist per checkout. Counters and reservation records must be changed in the same Inventory transaction.

## T1: Reserve one unit
READ COMMITTED is the proposed isolation level. Claim a durable idempotency record first. Within the same transaction:

```sql
UPDATE inventory.inventory_items
SET available_stock = available_stock - 1,
    reserved_stock = reserved_stock + 1,
    version = version + 1,
    updated_at = clock_timestamp()
WHERE sku = $1 AND available_stock >= 1
RETURNING sku;
```

If no row returns, persist the 409 OUT_OF_STOCK response with the idempotency key and commit, without inserting a reservation. If a row returns, insert a HELD reservation with a unique checkout_id and expiry = clock_timestamp() + interval '300 seconds', then store the response and commit. If any later insert fails, roll back the stock update too. A duplicate checkout_id must resolve to the existing reservation and never consume a second unit, even with a different API key. Validate missing SKUs separately as 404.

PostgreSQL serializes conflicting row updates and rechecks the UPDATE predicate after waiting. Thus the successful update is the contention decision; the transaction commit makes it durable. Do not implement SELECT available followed by an unconditional UPDATE.

## T2: Commit a paid reservation
Authenticate Checkout's service identity. It must have verified CAPTURED payment, matching checkout, amount and currency through Payment's API. Inventory does not call the external gateway.
1. BEGIN; lock reservation using SELECT ... FOR UPDATE.
2. If COMMITTED with the same payment_id, return prior success even if its old expires_at has passed. Different payment_id is a 409 conflict.
3. If RELEASED/EXPIRED, reject. If HELD but expired according to fresh database time after acquiring the lock, perform T3 expiry and return 409 RESERVATION_EXPIRED.
4. If valid HELD, acquire the inventory row and update reserved_stock -= 1, sold_stock += 1, version += 1. Mark COMMITTED, bind payment_id and committed_at. Commit.
No network calls occur while holding these locks. Confirmation and expiry both lock the same reservation first, then its stock row; only one terminal transition wins. Eligibility is evaluated under the reservation lock. An expiry worker cannot reverse a committed allocation.

## T3: Release / expire
Lock the reservation, then inventory row. Only HELD may release. Change reserved -= 1 and available += 1, update reservation to RELEASED or EXPIRED, append the appropriate Inventory outbox event, and commit. Repeated release/expiry of the same terminal hold is a no-op. COMMITTED cannot release through this endpoint; cancellations after purchase require a separate audited restocking workflow. Expiry worker selects due HELD rows with FOR UPDATE SKIP LOCKED and handles bounded batches. Every transition must recheck state under lock.

## T4: Payment processing and callbacks
Commit an INITIATED payment intent, durable idempotency record and stable provider key before calling the gateway. Call the gateway outside the transaction. In a new transaction lock the intent, update a legal outcome, and append PaymentFailed only for a definitive non-payment result (especially late reconciliation). Never emit PaymentFailed for UNKNOWN. Duplicate or out-of-order callbacks cannot downgrade CAPTURED/REFUNDED. Verify callback signature before processing; insert webhook_receipts and apply state changes together. Reconcile uncertainty by existing provider reference or stable provider key; a fresh key could double-charge.

## T5: Complete Checkout
Persist INITIATED checkout and item/address/price snapshots before outbound calls. Record reservation/payment IDs durably as available. After CAPTURED, enter COMMITTING_INVENTORY and call Inventory commit idempotently. Only after confirmed commitment, atomically set checkout SUCCESS and insert CheckoutCompleted into the Checkout outbox. Payment DB and Checkout DB are NOT a shared transaction.
If commit times out, query reservation/retry the same commit. Do not refund while commitment is ambiguous. If commit definitively fails due to expiry/release, enter REFUND_PENDING, request full refund with stable refund key, and reconcile until confirmed; no CheckoutCompleted is emitted. Refund failure remains actionable, not silently complete.

## T6: Consume CheckoutCompleted
BEGIN in Order DB; insert (consumer_name,event_id) into processed_events. If duplicate, stop safely. Enforce unique checkout_id as a second business-level guard against distinct event IDs for the same checkout. Validate snapshot and commitment evidence in the trusted event. Create order, items/address and OrderConfirmed outbox event in the same transaction. Commit, then acknowledge the broker message. On failure roll back all local changes and retry. A duplicate checkout with contradictory payload is quarantined/alerted rather than overwriting the order.

## T7: Outbox relay and downstream consumers
Claim bounded unpublished rows with a renewable lease; publish outside long database transactions. Mark published_at only after broker acknowledgement. A crash after publish but before marking causes redelivery; consumers deduplicate. Retry with exponential backoff and jitter; proposed 1s increasing to 60s. Persistent malformed events enter a dead-letter queue after a bounded attempt policy; alert and replay with the same event_id after repair. Do not discard paid purchases at retry exhaustion.
Shipment creation uses order_id as provider idempotency reference. Notification uses a unique source-event/channel key. Consumer deduplication alone cannot make external email or carrier side effects atomic: provider idempotency or reconciliation is also required.

## Consistency matrix

| Data/path | Model | Practical guarantee |
|---|---|---|
| Inventory mutation | Local ACID, explicit locks/conditional update | No negative stock; one terminal reservation transition |
| Payment record | Local ACID + provider reconciliation | Durable known outcome; ambiguity explicit |
| Checkout completion | Local ACID + orchestration recovery | Success and outgoing event commit together |
| Order creation | Eventual across services, local ACID | One order per checkout, assuming recovery progresses |
| Product availability display | Eventual/cached | Advisory only; reserve API decides availability |
| Notifications / shipping views | Eventual | May lag; replay/reconciliation handles interruption |

There is no cross-service serializable transaction and no claim of exactly-once message delivery. Business effects are deduplicated within documented keys and retention rules. During loss of authoritative Inventory DB connectivity, new reservations fail closed (503), not against cached stock. A lagging replica cannot decide reserve/commit eligibility.

## Recovery walkthroughs

| Failure | Recovery |
|---|---|
| Payment captured; Checkout crashes | Scan unfinished checkout attempts, query Payment by checkout_id, query/commit reservation, then write outbox or refund after definitive rejection |
| Capture at gateway; Payment DB update fails | Reconcile existing provider intent/key; never create a new charge |
| Order unavailable 30 seconds | Checkout event remains durable; committed inventory has no expiry release; Order resumes and deduplicates |
| Broker unavailable | Unpublished outbox rows remain; publishing resumes later |
| 3DS completes late | Payment updates CAPTURED; Checkout reconciliation attempts commit; refund if expired/released |
| Duplicate PaymentFailed after commitment | Inventory locks reservation and refuses to release COMMITTED stock |
| Client retry after lost response | Reuse key; return existing resource/progress without repeated mutation |

Checkout recovery workers claim attempts with leases/version checks; steps use deterministic operation keys. A recovered worker must not race a live worker into separate charges. One stable payment intent per checkout plus provider idempotency is mandatory. Post-sale returns and stock replenishment require a separate design; they are outside the fixed 100-unit invariant exercise.

## Concurrency trade-off and capacity limits
Chosen proposal: conditional stock UPDATE plus reservation locking; alternate: optimistic version compare-and-swap with bounded retries. A hot SKU still serializes on one row. More Inventory pods do not remove that bottleneck. Member 4 must define admission limits, bounded DB pools, queue/backpressure and load tests. A token bucket limits traffic; it is not a durable inventory consistency algorithm on its own. No 10,000-user or 500,000-RPS benchmark is claimed by this package.
