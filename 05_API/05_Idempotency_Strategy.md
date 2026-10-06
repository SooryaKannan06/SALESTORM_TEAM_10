# 5. Idempotency key implementation strategies

## Scope and generation
Customer generates a random key once per checkout operation (8–128 characters). Same operation retries reuse it. The server scopes keys by authenticated caller_id and operation, not globally. Internal keys are deterministic from checkout_id and action, e.g. checkout:{id}:reserve, checkout:{id}:pay, reservation:{id}:commit. Payment provider key is durable and stable; refund has its own stable key.

## Durable admission algorithm
1. Validate authentication, input and ownership. Canonicalize stable semantic fields (sorted object keys, normalized currency and quantities); hash the canonical representation using SHA-256. For payment token identity, use a keyed hash/fingerprint, never the raw token. Do not include transient headers/timestamps in the fingerprint.
2. INSERT idempotency_requests with primary key (caller_id,operation,idempotency_key), state IN_PROGRESS and resource_id. A unique constraint arbitrates concurrent claims. On conflict, read the existing record; compare hash.
3. Different hash: return 409 IDEMPOTENCY_KEY_REUSED. Same hash and COMPLETED: return stored acceptance/result. Same hash and IN_PROGRESS: return 202 with the existing resource location/progress. Never run a second payment attempt.
4. For short Inventory operations, execute claim + business change + final response inside one transaction. A rollback rolls everything back. For Checkout/Payment, commit the claim and durable resource before external work; a lease/versioned recovery worker resumes unfinished work.
5. Store response_code/body only after appropriate local commit. GET status is the current truth; replaying a stored 202 is not a promise that workflow status never changes.

## Business-level safeguards
API keys are only one layer. Unique checkout_id on reservations/payment_transactions/orders prevents duplicates with different request keys. Unique provider key and reference prevent duplicate financial records. Repeated reservation commitment returns its previously bound payment result; a different payment is rejected. Same consumer_name/event_id suppresses redelivery, while orders.checkout_id suppresses duplicate business events carrying new IDs.

## Provider uncertainty
Persist intent/key before calling the gateway. If the request or response is lost, query/retry the same provider operation. If the provider's idempotency retention has elapsed while the result is unknown, reconcile by durable provider reference/manual review; never blindly issue a new charge. Do not assume an adapter named authorizeAndCapture can guarantee a final result during timeouts or 3DS.

## Webhooks
Verify provider-specific signature over raw bytes, check signed timestamp/replay window, then deduplicate by provider + provider_event_id. Write webhook receipt, state transition and outgoing event in one transaction. If already applied, acknowledge without repeating side effects. Reject conflicting payload hashes for an existing event ID and alert. Enforce monotonic/legal transitions: a stale FAILED callback must not downgrade CAPTURED.

## Refunds
Full-refund demo allows one refund record per payment. Use the same provider refund key on retries; PENDING/UNKNOWN does not become SUCCEEDED until confirmed. Confirm captured amount/currency under a Payment row lock. A refund is permitted only after reservation commitment is definitively rejected; an ambiguous commit is reconciled first. Future partial refunds need cumulative-amount guards and separate refund operation IDs.

## Retention proposal
Keep API key outcomes for the 7-day retry window, consumer dedup records at least the maximum broker retention/replay window (proposed 30 days), and checkout/payment/order business uniqueness for the full record lifetime. Archive financial/audit data under the team's retention policy. Do not garbage-collect keys for unsettled workflows. Reject reuse of an expired client key or require a new explicit purchase; do not silently treat a late old key as a new charge. The demo retains all records rather than implementing cleanup.

## Failure expectations
- Two requests with the same key: one business action, same resource ID.
- Same key/different SKU or amount: 409, no mutation.
- Crash after provider capture: existing intent is reconciled, never charged with a new key.
- Duplicate CheckoutCompleted: one order and one OrderConfirmed business event.
- Cache outage: durable uniqueness remains authoritative.
