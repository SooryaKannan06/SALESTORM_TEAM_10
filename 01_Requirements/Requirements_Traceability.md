# SALESTORM: Requirements Traceability Matrix

This document maps the core business requirements to the architectural components and specific team member responsibilities to ensure complete coverage of the SALESTORM problem.

| Requirement ID | Description | Architectural Component | Team Member Ownership |
|---|---|---|---|
| REQ-01 | Handle 10,000 concurrent purchase attempts | Checkout Service, Inventory Service (Concurrency Control) | Member 1 (HLD) & Member 4 (Concurrency) |
| REQ-02 | Prevent overselling of 100 available units | Inventory Service, Inventory Database | Member 1 (Boundary) & Member 4 (Locking/Concurrency) |
| REQ-03 | Temporary inventory reservation & expiry | Inventory Service, Message Broker (Delayed events/Cron) | Member 2 (LLD, State Diagram) & Member 4 (Reliability) |
| REQ-04 | Safe and idempotent payment processing | Payment Service, Payment Database | Member 2 (LLD) & Member 3 (API/Idempotency) |
| REQ-05 | Consistent order lifecycle | Order Service, Message Broker | Member 2 (State Diagram) & Member 3 (Events) |
| REQ-06 | Recover gracefully from service failures | Message Broker, API Gateway (Circuit Breakers) | Member 1 (Async Design) & Member 4 (Recovery) |
| REQ-07 | High-scale read traffic (500k req/sec) | CDN, WAF, Distributed Cache (Redis) | Member 1 (HLD) & Member 4 (Scalability) |
| REQ-08 | Prevent duplicate reservations/orders | Inventory Service, Checkout Service, Order Service | Member 3 (Idempotency keys, DB Constraints) |

## Cross-Team Validation
- **Member 1 (Architecture):** Defines the boundaries so REQ-02 and REQ-03 are contained within the Inventory Service.
- **Member 2 (LLD):** Implements the SOLID patterns to satisfy REQ-04 and REQ-05.
- **Member 3 (Data):** Designs the DB schema and APIs to support REQ-02, REQ-04, and REQ-08.
- **Member 4 (Reliability):** Solves the exact mechanisms for REQ-01, REQ-02, and REQ-06.
