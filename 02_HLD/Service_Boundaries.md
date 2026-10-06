# SALESTORM: Service Boundaries & Domain Ownership

## 1. Domain Ownership Map
To ensure loose coupling and prevent data inconsistency, each service owns its logical data store/schema. Cross-service direct table writes are prohibited.

| Service | Domain Entities Owned | Description |
|---|---|---|
| **Product Service** | Product, Category | Manages catalog, read-heavy, heavily cached. |
| **Cart Service** | Cart, Cart Item | Manages ephemeral shopping session state. |
| **Sale Service** | Deal, Coupon, Sale Rules | Manages discounts and promotion rules. |
| **Inventory Service** | Inventory (Available, Reserved, Sold), Reservation | **AUTHORITATIVE** owner of stock quantities and reservation locks. |
| **Payment Service** | Payment | Manages transaction state, idempotency keys, and gateway interactions. The **authoritative** owner of payment state. |
| **Order Service** | Order, Order Item | Manages order lifecycle (Created, Confirmed, Cancelled). |
| **Fulfilment Service** | Shipment | Manages logistics integration and shipment tracking. |
| **Notification Service** | Notification Event | Manages delivery of SMS/Email. |

---

## 2. Service Boundary Matrix
This table defines exactly what each service reads, writes, and its dependencies. This is the **contract** for Members 2, 3, and 4.

| Service | Responsibility | Owns | Reads | Writes | Sync Dependencies | Async Events Produced/Consumed |
|---|---|---|---|---|---|---|
| **Product Service** | Product catalogue viewing | Product State | Products | Products (Admin only) | None | None |
| **Cart Service** | Cart management | Cart State | Cart items | Cart state | Product Service (to validate items) | None |
| **Sale Service** | Discount validation | Sale Rules | Deals, Coupons | Sale Config | None | None |
| **Inventory Service** | Inventory availability and reservation | Inventory state + reservation state | Inventory records | Inventory/reservation state | None (It is called *by* others) | **Consumes:** PaymentFailed<br>**Produces:** ReservationExpired, ReservationReleased |
| **Checkout Service** | Orchestrates the Buy Now flow | Checkout session state | Cart, Inventory, Sale | Checkout outbox state | Cart, Sale, Inventory, Payment (All Sync) | **Produces:** CheckoutCompleted (via Outbox) |
| **Payment Service** | Idempotent payment processing | Payment transaction state | Payment records | Payment state | Payment Gateway (Sync) | **Produces:** PaymentFailed (Only for late/reconciliation failures) |
| **Order Service** | Manages order lifecycle | Order lifecycle state | Orders | Order state | None (Driven by events) | **Consumes:** CheckoutCompleted<br>**Produces:** OrderConfirmed |
| **Fulfilment Service** | Delivery logistics | Shipment lifecycle | Shipment state | Shipment state | External Shipping API (Sync) | **Consumes:** OrderConfirmed |
| **Notification Service** | Customer alerts | Notification logs | Notification templates | Notification logs | External Notification API (Sync) | **Consumes:** OrderConfirmed, ShipmentUpdates |

## 3. Critical Boundary Rule
**Inventory Service is the ONLY service that can mutate the `INVENTORY` or `INVENTORY_RESERVATION` database tables.**
- Checkout Service CANNOT update inventory.
- Order Service CANNOT update inventory.
- Payment Service CANNOT update inventory.

## 4. Payment Ownership & Checkout Outbox
- The **Payment Service** owns the authoritative payment transaction state in its own database.
- The **Checkout Service** owns the orchestration logic and its local Transactional Outbox.
- This means the Payment DB state and the Checkout Outbox are **separate local ownership boundaries**. They are not atomically committed together via a distributed 2PC.
- The architecture relies on idempotency and reconciliation to bridge failures between these two systems (e.g., if Checkout crashes after Payment succeeds).

## 5. Payment Failure Feedback Loop
- **Immediate Failure (Normal):** If the external payment gateway immediately rejects the card (e.g., insufficient funds), the Payment Service responds synchronously to the Checkout Service, which immediately returns a failure to the customer.
- **Late/Reconciliation Failure (Async):** If the payment fails late (e.g., timeout, delayed gateway response, reconciliation), the Payment Service publishes a `PaymentFailed` event to the Message Broker. The Inventory Service consumes this event to authoritatively release the reservation.
