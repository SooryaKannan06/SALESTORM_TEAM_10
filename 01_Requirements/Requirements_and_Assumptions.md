# SALESTORM: Requirements & Assumptions

## 1. Problem Statement
The SALESTORM e-commerce platform is preparing for a high-volume flash sale featuring limited-stock products. The system is expected to experience sudden and massive traffic spikes, with up to 10,000 customers simultaneously competing to purchase just 100 available units of a highly desirable product. The current architecture must be redesigned to handle this extreme concurrency without crashing, overselling inventory, or creating inconsistent order and payment states.

## 2. Business Objective
To design a highly scalable, robust e-commerce architecture that successfully processes high-concurrency flash sales, protects limited inventory from overselling, provides temporary inventory reservation, ensures idempotent payment processing, and maintains a consistent order lifecycle even in the event of partial system failures.

## 3. Functional Requirements
### STRICT GUARANTEES
- **Inventory Reservation:** Customers must be able to temporarily reserve inventory during checkout.
- **Reservation Expiry:** Unpaid or timed-out reservations must automatically expire and release the inventory back to the available pool.
- **Payment Processing:** The system must process payments securely and reliably.
- **Order Creation:** Every successfully completed payment must eventually result in a valid confirmed order, or enter a defined reconciliation/compensation path.
- **Duplicate Prevention:** Duplicate checkout or payment requests must be handled idempotently and must not result in duplicate reservations, payments, or orders.

### TARGETS
- **Product Discovery & Viewing:** Users should be able to browse and view flash-sale products seamlessly.
- **Cart Management:** Users can add items to their shopping cart.
- **Sale & Promotions:** Apply discounts and sale rules via the Sale Service.
- **Checkout Flow:** Users can initiate the checkout process from their cart.
- **Fulfilment & Shipment:** Orders should be forwarded to fulfilment and shipment providers.
- **Notifications & Tracking:** Customers should receive email/SMS notifications for order confirmation, shipment, and delivery tracking.

## 4. Non-Functional Requirements
### STRICT GUARANTEES
- **No Overselling:** The system must strictly guarantee that the number of successfully sold units does not exceed the available inventory (e.g., 100 units).
- **Payment Reliability:** Defined recovery paths must exist for payment gateway timeouts or failures.
- **Idempotency:** All state-mutating operations (reservation, payment, order creation) must be idempotent.
- **Data Consistency:** Order and Inventory states must eventually be consistent.

### TARGETS
- **Low Latency:** Product discovery and cart operations should be fast and responsive.
- **High Throughput:** The system should absorb sudden spikes in traffic smoothly.
- **High Availability:** Core business functions should remain available even if auxiliary services fail.

## 5. Performance Requirements
- **Normal Traffic:** Handle approximately 10,000 requests/sec with low latency.
- **Flash-Sale Traffic:** Architecturally support scaling to handle up to 500,000 requests/sec at the edge/gateway level.

## 6. Scalability Requirements
- **Horizontal Scaling:** All stateless business services (Product, Cart, Sale, Checkout, Order) must be horizontally scalable.
- **Traffic Absorption:** The architecture must use CDN, Caching, and Load Balancing to filter and absorb traffic before it reaches the scarce inventory resource.

## 7. Availability Requirements
- The system should maintain high availability for browsing and cart operations.
- The checkout and reservation flow must fail gracefully (e.g., returning "out of stock" immediately) when inventory is depleted, rather than timing out.

## 8. Consistency Requirements
- **Strong Consistency:** Inventory reservation must use strong consistency to prevent overselling.
- **Eventual Consistency:** Order confirmation, notifications, and downstream processing can rely on eventual consistency via asynchronous messaging.

## 9. Security Requirements
- **Authentication/Authorization:** Users must be authenticated before checkout.
- **Data Protection:** HTTPS for all communications. Secure handling of payment information (PCI-DSS compliance scope).
- **Abuse Protection:** Rate limiting and WAF must be implemented to prevent bot abuse during the flash sale.

## 10. Reliability Requirements
- **Graceful Degradation:** Failure in non-critical services (e.g., Notification) must not block the core checkout and payment flow.
- **Fault Tolerance:** Circuit breakers, retries, and dead-letter queues must be used for external dependencies (Payment Gateway, Shipping).
- **Recovery:** Automated recovery mechanisms for order processing if a service fails post-payment.

## 11. Observability Requirements
- **Metrics:** Track request rate, latency, error rate, reservation success/failure rates, and payment success/failure rates.
- **Tracing:** Distributed tracing across Checkout, Inventory, Payment, and Order workflows.
- **Logging:** Structured audit logs for all critical state changes (Reservation created, Payment confirmed, Order created).

## 12. Assumptions
- Users are authenticated via an external Identity Provider (IdP) before initiating checkout.
- The Product Catalogue is extremely read-heavy and can be heavily cached at the CDN and API Gateway layers.
- The flash-sale product will become a "hot key" in the database.
- The **Inventory Service** is the sole authoritative owner of inventory state. No other service can directly modify inventory records.
- Payments are processed by an external third-party Payment Gateway.
- Shipments and Fulfilment are handled by external delivery partners.
- Critical business operations require durable, persistent state.
- Asynchronous processing is acceptable for downstream workflows (Orders to Fulfilment, Notifications).
- Payment Service remains the authoritative owner of payment transaction state, enabling reconciliation if Checkout crashes after payment succeeds.

## 13. Constraints
- The solution must be deployable in a cloud-native environment (containers/Kubernetes).
- The inventory bottleneck cannot be purely solved by scaling the database; the concurrency-control mechanism defined by Member 4 is required, guaranteeing that no more than the 100 available units can be successfully reserved.

## 14. System Scope
**In Scope:**
- CDN/WAF and API Gateway.
- Core Microservices: Product, Cart, Sale, Inventory/Reservation, Checkout, Payment, Order, Notification, Shipment.
- Database architecture for the above services.
- Inter-service communication (Sync via REST/gRPC, Async via Message Broker).

## 15. Out of Scope
- Implementation of the external Payment Gateway.
- Implementation of external Shipping/Fulfilment provider systems.
- Front-end UI/UX design.
- Identity Provider implementation (assume OAuth2/OIDC exists).
