# SALESTORM: Sync vs Async Communication Boundaries

## 1. Synchronous Communication
Operations requiring an immediate user or business decision remain synchronous to provide real-time feedback during the critical path of the flash sale.

**Selected Technology:** REST (JSON over HTTPS) or gRPC (for internal service-to-service communication).

### Key Synchronous Flows:
- **Client → API Gateway → Product/Sale Service:** Real-time catalog browsing and deal evaluation.
- **Client → API Gateway → Cart Service:** Real-time cart updates.
- **Checkout Service → Inventory Service:** The checkout process *must* know immediately if inventory is successfully reserved. If inventory is 0, the process halts and returns an error to the user immediately.
- **Checkout Service → Payment Service → Payment Gateway:** The payment must be authorized synchronously so the user is informed of immediate success or failure (e.g., declined card, insufficient funds) while they are still in the session.

**Why Synchronous?**
- Immediate validation and feedback to the customer.
- Business requirement to immediately stop the flow if inventory is unavailable.
- Prevents complex distributed rollback scenarios during the critical reservation phase.

---

## 2. Asynchronous Communication
Operations that do not require the user to wait, or workflows that can be processed eventually, are designed asynchronously. This protects the system from bottlenecks and provides resilience against downstream failures.

**Selected Technology:** Message Broker (e.g., Kafka or RabbitMQ, to be finalized in Member 4's ADR).

### Key Asynchronous Flows:
- **Checkout Service → Transactional Outbox → Message Broker (CheckoutCompleted):** Once payment succeeds, Checkout durably persists its state and the `CheckoutCompleted` event in the same local transaction (Transactional Outbox pattern). An outbox publisher then reliably relays this event to the broker. The user sees a "Payment successful; order creation pending" screen immediately.
- **Message Broker → Order Service:** Order Service idempotently consumes the `CheckoutCompleted` event to asynchronously build the persistent order record.
- **Order Service → Message Broker (OrderConfirmed):** Published when the order is successfully created in the Order DB.
- **Message Broker → Fulfilment / Notification Service:** These services independently consume `OrderConfirmed` to trigger shipping and send confirmation emails.
- **Reservation Expiry:** Inventory Service (via TTL or internal cron) determines a reservation has expired, performs the authoritative release in its own database, and then optionally publishes a `ReservationExpired` event for downstream consumers.

---

## 3. Handling Payment & Checkout Failures

The architecture distinguishes four specific failure cases to guarantee reliability without relying on distributed 2PC transactions.

**A. Immediate payment failure:**
- Flow: Payment Gateway → Payment Service → Checkout Service → immediate failure response to the customer.
- Result: The user is informed, and the reservation naturally expires via the Inventory Service.

**B. Payment timeout / unknown result:**
- Flow: Payment Service cannot determine the gateway's status. It relies on a reconciliation/webhook/status recovery mechanism to find the final payment state.
- Result: If ultimately failed, Payment Service publishes a `PaymentFailed` event to the broker, which the Inventory Service consumes to authoritatively release the reservation.

**C. Payment success + Checkout crash:**
- Scenario: Payment Gateway succeeds, Payment Service records SUCCESS, but Checkout Service crashes *before* it can write to its Outbox.
- Recovery Flow: 
  1. Payment Service retains durable SUCCESS state.
  2. A payment reconciliation/status recovery mechanism detects the successful payment without a corresponding completed checkout.
  3. Checkout recovery resumes the flow and creates the required `CheckoutCompleted` event in the Outbox.
  4. Outbox → Broker → Order Service processes it normally.
- Result: No paid order is lost.

**D. Outbox / Broker failure:**
- Scenario: Checkout writes the `CheckoutCompleted` event to its local Outbox, but the Message Broker is unavailable.
- Flow: The event remains durable in the Checkout Outbox. The local publisher continues to retry.
- Result: Once the Broker recovers, the event is delivered to the Order Service.
