# SALESTORM — Team 10

**System design for a flash-sale platform where 10,000 customers compete for 100 units.**

SALESTORM explores how an e-commerce system can protect limited inventory, process payments safely, and recover orders after partial service failures. This repository brings together Team 10's requirements, high-level and low-level designs, database schemas, API contracts, reliability decisions, and presentation material.

> **Current status:** Architecture and contract deliverables. The repository includes PostgreSQL SQL scripts, OpenAPI and JSON Schema contracts, Markdown documents, and Mermaid diagrams. Application services, a frontend, deployment manifests, and executable load tests are not included. Performance figures are design targets, not verified benchmark results.

## The problem

A flash sale creates sudden traffic spikes against a small inventory pool. The design addresses:

- 10,000 simultaneous purchase attempts for an initial stock of 100 units.
- Prevention of overselling and duplicate reservations, payments, or orders.
- Temporary reservations with safe release and expiry.
- Payment declines, ambiguous gateway outcomes, and late callbacks.
- Recovery when payment succeeds but checkout or order processing fails.
- A proposed edge traffic target of up to 500,000 requests per second, distinct from backend purchase concurrency.

The database/API package models an initial purchase containing **one product and one unit**. Payment gateways, shipping providers, and the identity provider are external integrations.

## Repository guide

| Directory | Contents |
|---|---|
| [01_Requirements](01_Requirements/) | Business requirements, assumptions, constraints, and team traceability |
| [02_HLD](02_HLD/) | Architecture overview, service ownership, communication boundaries, and deployment diagrams |
| [03_LLD](03_LLD/) | Classes, purchase/payment/recovery sequences, and state machines |
| [04_Database](04_Database/) | ER diagram, schemas, keys, indexes, constraints, transaction boundaries, SQL, and stock seed |
| [05_API](05_API/) | REST specification, OpenAPI contract, idempotency strategy, event schemas, and examples |
| [06_SOLID](06_SOLID/) | Mapping of SOLID principles to service internals |
| [07_Design_Patterns](07_Design_Patterns/) | Saga, Factory, and Strategy pattern documentation |
| [08_Scalability_Reliability](08_Scalability_Reliability/) | Concurrency, reservation expiry, retries, recovery, admission control, and stress scenarios |
| [09_Security_Observability](09_Security_Observability/) | Authentication, authorization, payment security, secrets, threats, metrics, tracing, and audit logging |
| [10_ADR](10_ADR/) | Nine architecture decision records covering concurrency, idempotency, expiry, recovery, scaling, security, and observability |
| [11_AI_Assisted_Validation](11_AI_Assisted_Validation/) | AI assistance disclosure and engineering ownership statement |
| [12_Presentation](12_Presentation/) | Presentation outlines and technical defense questions |

## Architecture and service ownership

The proposed architecture places CDN/WAF, load balancing, and an API Gateway before the business services. Checkout orchestrates synchronous inventory and payment operations; durable events support asynchronous order creation and downstream work.

| Service | Responsibility |
|---|---|
| Product | Catalogue and category data; cacheable product reads |
| Cart | Shopping cart and item management |
| Sale | Deals, coupons, and promotion rules |
| Checkout | Purchase orchestration, checkout progress, and completion outbox |
| Inventory | Sole owner of stock, reservations, commitment, release, and expiry |
| Payment | Payment intents, provider interactions, callbacks, refunds, and reconciliation |
| Order | Idempotent order creation and order lifecycle |
| Fulfilment / Shipment | External delivery integration and shipment tracking |
| Notification | Customer notifications triggered by business events |

Each service owns its logical data. Cross-service references do not authorize another service to write its tables. Payment gateway calls occur outside database transactions.

### Purchase flow in the database/API contract

1. Authenticate the customer, validate the purchase, and persist a checkout attempt with item, price, and address snapshots.
2. Reserve one unit through Inventory. Reject unavailable stock without starting a payment.
3. Persist a payment intent and stable provider idempotency key before contacting the gateway.
4. Reconcile pending or unknown payment outcomes instead of assuming a timeout means failure.
5. After confirmed capture, commit the reservation through Inventory. A definitive expiry/release rejection enters the refund workflow.
6. Atomically persist checkout success and `CheckoutCompleted` in the Checkout outbox.
7. Publish the event through an outbox relay. Order consumes it idempotently and persists the order and `OrderConfirmed` together.
8. Fulfilment and Notification process downstream events asynchronously.

For transaction details, read [Transactions and Consistency](04_Database/03_Transactions_and_Consistency.md).

## Proposed technologies

These technologies are documented design choices; their infrastructure is not provisioned by this repository.

| Area | Documented proposal |
|---|---|
| Durable storage | PostgreSQL with service-owned schemas, constraints, idempotency records, and outboxes |
| Cache and fast path | Redis; reliability documents also propose atomic Lua reservation scripts |
| Event streaming | Kafka with retries, consumer deduplication, and dead-letter handling |
| API contracts | REST, OpenAPI 3.0.3, and JSON Schema event contracts |
| Deployment and scaling | Containers, Kubernetes, horizontal scaling, admission control, and connection pooling |
| Security | OAuth2/OIDC, JWT validation, TLS/mTLS, rate limiting, and tokenized payment handling |
| Observability | OpenTelemetry, Prometheus, Grafana, Tempo, and Loki |
| Design diagrams | Mermaid (`.mermaid` and `.mmd`) |

## Database and consistency

The SQL defines eight logical schemas: `product`, `sale`, `checkout`, `inventory`, `payment`, `orders`, `fulfilment`, and `notification`.

Key records include checkout attempts, inventory reservations, payment transactions, refunds, webhook receipts, orders, shipments, notifications, idempotency requests, outbox events, and processed-event records.

For the fixed-stock exercise:

```text
available_stock + reserved_stock + sold_stock = 100
```

Stock counters remain non-negative. The database/API proposal updates stock and reservation records within local ACID transactions, uses conditional stock updates for reservation, and locks reservations for commitment or release. Cross-service order creation and notifications are eventually consistent.

Delivery is designed to be **at least once**. Stable event IDs, consumer deduplication, business uniqueness constraints, and provider idempotency prevent repeated business effects within the documented scope.

## API and event contracts

Open [openapi.yaml](05_API/openapi.yaml) in an OpenAPI-compatible editor or viewer to inspect request bodies, responses, and security definitions. Its `http://localhost:3000` server entry is a contract placeholder; no API server is included.

| Area | Contract paths |
|---|---|
| Checkout | `/api/v1/checkout`, `/api/v1/checkout/{checkout_id}` |
| Inventory | `/v1/inventory/reservations`, `/v1/inventory/reservations/{reservation_id}`, plus `/commit` and `/release` |
| Payments | `/v1/payments`, `/v1/payments/status`, `/v1/payments/{payment_id}/refunds`, `/v1/payments/webhooks` |
| Orders | `/api/v1/orders/{order_id}`, `/api/v1/orders/{order_id}/tracking` |
| Products | `/api/v1/products`, `/api/v1/products/{sku}` |
| Cart | `/api/v1/cart`, `/api/v1/cart/items` |

See the [REST specification](05_API/04_REST_API_Specification.md) and [idempotency strategy](05_API/05_Idempotency_Strategy.md) for operation details. Idempotency keys are scoped by caller and operation; retries reuse the original key, while conflicting payload reuse is rejected.

| Event | Producer | Consumers |
|---|---|---|
| `CheckoutCompleted` | Checkout | Order |
| `PaymentFailed` | Payment | Inventory, Checkout |
| `OrderConfirmed` | Order | Fulfilment, Notification |
| `ReservationExpired` | Inventory | Checkout |
| `ReservationReleased` | Inventory | Checkout |
| `ShipmentUpdated` | Fulfilment | Order, Notification |

Machine-readable definitions are in [event_schemas](05_API/event_schemas/), with sample messages in [examples](05_API/examples/). Read [Event Payloads](05_API/06_Event_Payloads.md) for envelope, routing, and delivery rules.

## Getting started

### Browse the design

```bash
git clone https://github.com/SooryaKannan06/SALESTORM_TEAM_10.git
cd SALESTORM_TEAM_10
```

Start with [Requirements and Assumptions](01_Requirements/Requirements_and_Assumptions.md), then [Architecture Overview](02_HLD/Architecture_Overview.md), [Service Boundaries](02_HLD/Service_Boundaries.md), and the database/API documents. Use a Mermaid-compatible viewer for standalone diagram files.

### Load the proposed PostgreSQL schema

Prerequisites: a running PostgreSQL instance, `createdb` and `psql`, and an account permitted to create a database and schemas. Run from the repository root against a fresh development database:

```bash
createdb salestorm
psql -v ON_ERROR_STOP=1 -d salestorm -f 04_Database/schema.sql
psql -v ON_ERROR_STOP=1 -d salestorm -f 04_Database/seed.sql
```

Inspect the seeded stock:

```bash
psql -d salestorm -c "SELECT sku, total_stock, available_stock, reserved_stock, sold_stock FROM inventory.inventory_items;"
```

The seed creates inventory for `FLASH-001` with 100 total and available units. It does not populate the catalogue, customers, payments, or orders. Table creation and seed insertion are not rerunnable migrations; use a fresh database for this walkthrough. Loading SQL does not start the proposed services.

## Design alignment needed

The team documents currently contain alternative proposals that must be reconciled before implementation:

| Topic | Database/API package | Reliability / ADR / presentation material |
|---|---|---|
| Reservation authority | PostgreSQL conditional updates and local transactions decide durable allocation | Redis Lua fast path followed by PostgreSQL persistence and reconciliation |
| Reservation expiry | 300 seconds (5 minutes) in the transaction proposal | 600 seconds (10 minutes) in reliability documents |
| Reservation states | `HELD`, `COMMITTED`, `RELEASED`, `EXPIRED` | Uses labels including `RESERVED`, `PAYMENT_PENDING`, `CONFIRMED`, and `SOLD` |
| Order creation trigger | Checkout outbox publishes `CheckoutCompleted` after payment capture and inventory commitment | Some ADR/presentation documents describe Payment publishing `salestorm.payment.completed` directly for Order |

The Redis/PostgreSQL proposal explicitly acknowledges a non-atomic dual-write boundary and a fail-closed recovery policy. It requires implementation and failure testing before its no-oversell goal can be treated as verified.

Some database/API README files reference `00_Integration_Contract.md`, and the AI disclosure references `simulation/flash_sale_simulation.py`; those files are absent from the current checkout. Numerical latency, capacity, and measured-result examples in presentation material are not accompanied by executable tests or result artifacts here.

## Validation roadmap

Before claiming implementation readiness, the team should:

- Agree on one inventory authority, reservation TTL, state vocabulary, and order event producer.
- Validate SQL and contracts, then implement service handlers, outbox relays, expiry workers, and reconciliation workers.
- Test concurrent reservations against 100 units, including release, expiry, and commitment races.
- Test duplicate requests/events, conflicting key reuse, unknown payments, late capture, and refund recovery.
- Test checkout crashes, order outages, broker outages, and database/cache failover.
- Record measured throughput and latency separately from design targets.

## Team contributions

The [Requirements Traceability Matrix](01_Requirements/Requirements_Traceability.md) divides responsibilities across four members:

| Member | Primary contribution |
|---|---|
| 1 | Requirements, high-level architecture, service boundaries, and communication design |
| 2 | Low-level design, classes, sequences, state machines, SOLID, and design patterns |
| 3 | ER model, database schemas, transactions, APIs, idempotency, and event contracts |
| 4 | Concurrency, scalability, reliability, security, observability, ADRs, and final presentation support |

See [AI Usage Note](11_AI_Assisted_Validation/AI_USAGE_NOTE.md) for the repository's disclosure of AI assistance and student engineering ownership.
