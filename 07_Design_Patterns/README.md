# 07_Design_Patterns: Design Patterns Implementation Index

**Team Role**: Member 2 (Detailed Design & Object Models)  
**System Scope**: Checkout, Inventory, Payment, and Order Modules  
**Architecture Contract**: Strictly aligned with Member 1's High-Level Architecture (Checkout as Orchestrator, Asynchronous Order Creation).

---

## Deliverables Summary

This directory documents the core object-oriented and distributed reliability patterns implemented across the assigned domains:

1. **[01_saga_pattern.md](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/07_Design_Patterns/01_saga_pattern.md)**:
   * Checkout-led synchronous orchestration paired with compensating rollbacks and local Transactional Outbox.
   * Forward and compensating action matrix.
   * Explicit modeling of failure scenarios, including **Payment Success + Checkout Crash** reconciliation.
   * Sequence diagrams and TypeScript orchestration logic.

2. **[02_factory_pattern.md](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/07_Design_Patterns/02_factory_pattern.md)**:
   * Dynamic payment gateway resolution (`PaymentGatewayFactory`) based on currency and localized routing rules.
   * Invariant-preserving asynchronous aggregate construction (`OrderFactory`) triggered upon consuming `CheckoutCompletedEvent`.
   * Class diagrams and aggregate creation code.

3. **[03_strategy_pattern.md](file:///c:/Users/Yugabharathi/Documents/System%20design%20Hackathon%20member%202/07_Design_Patterns/03_strategy_pattern.md)**:
   * Payment Processing Strategies (`CreditCardPaymentStrategy`, `UPIPaymentStrategy`, `DigitalWalletPaymentStrategy`).
   * Inventory Concurrency Strategies (`IllustrativeOptimisticLockingStrategy`, `IllustrativeTokenBucketStrategy`) presented as illustrative alternatives respecting **Member 4's exclusive authority over final concurrency implementation**.
   * Strategy context and dynamic runtime swapping logic.
