# 1. Entity-Relationship diagram

The critical diagram shows service-owned tables; solid edges are SQL foreign keys only. Table prefixes are schema owners. The schema enforces at most one item per checkout/order for the demo, even though the general collection relationship is shown as one-to-many. Supporting tables are in the second diagram. Operational outbox/idempotency tables are documented in the data dictionary.

```mermaid
erDiagram
    checkout_checkout_attempts {
        uuid checkout_id PK
        text customer_id
        text status
        uuid reservation_id UK
        uuid payment_id UK
        bigint amount_minor
        jsonb delivery_address
    }
    checkout_checkout_items {
        uuid item_id PK
        uuid checkout_id FK
        text sku
    }
    inventory_inventory_items {
        text sku PK
        integer available_stock
        integer reserved_stock
        integer sold_stock
    }
    inventory_reservations {
        uuid reservation_id PK
        uuid checkout_id UK
        text sku FK
        text status
        uuid payment_id UK
        timestamptz expires_at
    }
    payment_payment_transactions {
        uuid payment_id PK
        uuid checkout_id UK
        uuid reservation_id UK
        bigint amount_minor
        text status
    }
    payment_refunds {
        uuid refund_id PK
        uuid payment_id FK
        bigint amount_minor
        text status
    }
    orders_orders {
        uuid order_id PK
        uuid checkout_id UK
        text customer_id
        uuid reservation_id UK
        uuid payment_id UK
        text status
        bigint amount_minor
        jsonb delivery_address
    }
    orders_order_items {
        uuid item_id PK
        uuid order_id FK
        text sku
    }
    checkout_checkout_attempts ||--o{ checkout_checkout_items : contains
    inventory_inventory_items ||--o{ inventory_reservations : contains
    payment_payment_transactions ||--o{ payment_refunds : contains
    orders_orders ||--o{ orders_order_items : contains
```

## Cross-service logical references (no foreign keys)

| Source field | Target | Reason |
|---|---|---|
| reservations.checkout_id | checkout_attempts.checkout_id | Reservation correlation |
| payment_transactions.checkout_id | checkout_attempts.checkout_id | One payment intent per checkout |
| payment_transactions.reservation_id | reservations.reservation_id | Payment for the held unit |
| reservations.payment_id | payment_transactions.payment_id | Committed payment binding |
| orders.checkout_id | checkout_attempts.checkout_id | Deduplicate order creation |
| orders.payment_id / reservation_id | Payment / Inventory | Trace committed purchase |
| sku across services | product.products.sku | Stable catalogue identifier |
| shipments.order_id / notifications.order_id | orders.orders.order_id | Fulfilment and communication |
| customer_id | Identity provider subject | Authenticated identity |

## Supporting domains

```mermaid
erDiagram
    product_categories {
        uuid category_id PK
    }
    product_products {
        uuid product_id PK
        uuid category_id FK
        text sku UK
    }
    sale_sales {
        uuid sale_id PK
    }
    sale_deals {
        uuid deal_id PK
        uuid sale_id FK
        text sku
    }
    sale_coupons {
        uuid coupon_id PK
        uuid sale_id FK
        timestamptz expires_at
    }
    fulfilment_shipments {
        uuid shipment_id PK
        uuid order_id UK
        text status
    }
    notification_notifications {
        uuid notification_id PK
        uuid order_id
        uuid source_event_id
        text status
    }
    product_categories ||--o{ product_products : contains
    sale_sales ||--o{ sale_deals : contains
    sale_sales ||--o{ sale_coupons : contains
```
