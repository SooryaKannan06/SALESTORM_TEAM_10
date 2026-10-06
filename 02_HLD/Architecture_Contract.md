# SALESTORM: Architecture Contract for Other Team Members

This document establishes the strict architectural boundaries that the rest of the team MUST follow to ensure our final hackathon submission is cohesive, logically sound, and structurally consistent. 

**Do NOT change these boundaries without coordinating with Member 1.**

---

## MEMBER 2 CONTRACT: Low-Level Design (LLD)
*Your task is to design the classes and internal logic of the services.*
- **Service Boundaries:** You are designing the internals of the Inventory Service, Payment Service, and Order Service.
- **Checkout Flow (Purchase/Reservation Sequence):** Assume Checkout orchestrates the flow. Your sequence diagram should show: Checkout -> Inventory (Reserve) -> Payment (Pay) -> Outbox (Save) -> Broker (Publish).
- **Payment Flow:** Your payment sequence must show idempotent handling of external gateway responses, synchronous immediate failure returns, and returning success/failure to Checkout.
- **Order Flow:** Your order sequence must begin with consuming a CheckoutCompleted event from the Message Broker (not a direct REST call).
- **State Diagrams:** Design the state machine for Reservation (AVAILABLE -> RESERVED -> CONFIRMED / RELEASED) and Order (CREATED -> PROCESSING -> SHIPPED). Keep it strictly within the owning service.

---

## MEMBER 3 CONTRACT: Data & API Engineering
*Your task is to design the database schemas, APIs, and Event payloads.*
- **Domain Ownership:** 
  - Each service owns its logical database schema. Cross-service database writes are strictly prohibited.
  - Product lives in Product DB.
  - Sale/Deals live in Sale DB.
  - Inventory and Inventory_Reservation live strictly in Inventory DB.
  - Payment lives in Payment DB.
  - Order lives in Order DB.
- **Payment vs Checkout Outbox Boundary:** The Payment Service owns the authoritative payment transaction state. The Checkout Service owns its local outbox. They are separate local ownership boundaries. Do not merge them into a single atomic database schema.
- **API Boundaries:** Design REST/gRPC endpoints for Checkout calling Inventory (POST /inventory/reserve) and Payment (POST /payments/process).
- **Event Boundaries:** Define the schema for asynchronous messages flowing through the Message Broker:
  - CheckoutCompletedEvent (produced by Checkout via Outbox)
  - PaymentFailedEvent (produced by Payment only for late/reconciliation failures, consumed by Inventory)
  - OrderConfirmedEvent (produced by Order Service, consumed by Fulfilment/Notification)
  - ReservationExpiredEvent (produced by Inventory)
- **Inventory Authority:** NO diagrams or schemas should show the Order Service writing to the Inventory tables. Only the Inventory Service does this.

---

## MEMBER 4 CONTRACT: Scalability, Reliability & Concurrency
*Your task is to solve the exact concurrency algorithm, failure modes, and ADRs.*
- **Inventory Contention:** The bottleneck is contained inside the Inventory Service. You must design the exact algorithm (e.g., Optimistic locking, pessimistic locking, or Redis single-threaded Lua script) that prevents overselling the 100 units among the 10,000 requests hitting the Inventory API.
- **Reservation Lifecycle:** You must design the reliability mechanism for expiring unpaid reservations (e.g., cron job, TTL, or delayed message queue). Note that Inventory Service authoritatively performs the release.
- **Failure Boundaries:** You must define circuit breaker logic for when the Payment Service calls the external Payment Gateway. You also manage the Transactional Outbox relay logic.
- **Crash Recovery (Payment Success + Checkout Crash):** If Checkout crashes after Payment succeeds but before saving to the Outbox, the durable Payment state must be reconciled to resume Checkout. You own the exact implementation of this reconciliation loop.
- **Security & Observability:** Assume API Gateway handles WAF/Rate Limiting. You must define the distributed tracing context (correlation IDs) passed between these microservices.
- **Technology ADRs:** You are responsible for finalizing the exact technologies for the Message Broker, Relational Databases, and Distributed Cache. Ensure these align with the HLD.
