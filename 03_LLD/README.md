# 03_LLD: Low-Level Design Deliverables

**Team Role**: Member 2 (Detailed Design & Object Models)  
**System Scope**: Detailed Design for Checkout, Inventory, Payment, and Order Modules  
**Architecture Contract**: Strictly aligned with Member 1's High-Level Architecture (Checkout as Orchestrator, Asynchronous Order Creation).

---

## Deliverables Index

1. **[01_service_and_communication_boundaries.md](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/01_service_and_communication_boundaries.md)**:
   * End-to-end boundary topology: Client $\rightarrow$ CDN/WAF $\rightarrow$ Load Balancer $\rightarrow$ API Gateway $\rightarrow$ Checkout Service.
   * Synchronous path (Checkout $\rightarrow$ Inventory $\rightarrow$ Payment) vs. Asynchronous path (Checkout Outbox $\rightarrow$ Broker $\rightarrow$ Order Service).
   * Checkout local Transactional Outbox and status reconciliation boundaries.
2. **[02_class_diagrams.md](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/02_class_diagrams.md)**:
   * Domain-Driven Design (DDD) object models for Checkout, Inventory, Payment, and Order domains.
   * Entities, Value Objects, Ports (`IInventoryClient`, `IPaymentClient`), and Repositories with zero cross-database coupling.
3. **[03_sequence_diagrams.md](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/03_sequence_diagrams.md)**:
   * Sequence 1: End-to-End Purchase Flow (Orchestrated by Checkout Service).
   * Sequence 2: Critical Payment Processing & 3DS Webhook Flow.
   * Sequence 3: Failure & Recovery Flow (Payment Success + Checkout Crash reconciliation).
4. **[04_state_machines.md](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/04_state_machines.md)**:
   * State machine for `CheckoutAttempt` lifecycle.
   * State machine for post-purchase `Order` lifecycle.
   * State machine for `Reservation` lifecycle.
   * State machine for `PaymentTransaction` lifecycle.

---

## Diagram Source Files (`.mermaid`)
All visual diagrams are available in the [03_LLD/diagrams/](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams) directory:
* [service_boundaries.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/service_boundaries.mermaid)
* [class_diagram.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/class_diagram.mermaid)
* [purchase_reservation_flow.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/purchase_reservation_flow.mermaid)
* [payment_processing_flow.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/payment_processing_flow.mermaid)
* [order_recovery_flow.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/order_recovery_flow.mermaid)
* [checkout_state_machine.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/checkout_state_machine.mermaid)
* [order_state_machine.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/order_state_machine.mermaid)
* [reservation_state_machine.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/reservation_state_machine.mermaid)
* [payment_state_machine.mermaid](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/03_LLD/diagrams/payment_state_machine.mermaid)
