# 2. Database schemas: keys, indexes and constraints

Execute schema.sql once against an empty demo database. No destructive DROP statements are included. seed.sql initializes only the critical inventory example. Application code must update updated_at and increment versions. Schema creation does not configure authentication or grants.

## Ownership and enforcement
Use separate non-superuser runtime roles, each with USAGE on its own schema and only required table privileges; do not grant access to other service schemas. Migrations use a separate owner role. Sharing an instance is a demo convenience, not permission to join/write across service boundaries. Payment and Checkout commits remain separate.

## Data dictionary

### product.categories
| Column | Type | Rules / meaning |
|---|---|---|
| `category_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `name` | `text` | NOT NULL UNIQUE  |


### product.products
| Column | Type | Rules / meaning |
|---|---|---|
| `product_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `category_id` | `uuid` | NOT NULL REFERENCES product.categories(category_id)  |
| `sku` | `text` | NOT NULL UNIQUE  |
| `name` | `text` | NOT NULL  |
| `unit_price_minor` | `bigint` | NOT NULL  |
| `currency` | `char(3)` | NOT NULL DEFAULT 'INR'  |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `unit_price_minor >= 0`

### sale.sales
| Column | Type | Rules / meaning |
|---|---|---|
| `sale_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `name` | `text` | NOT NULL  |
| `starts_at` | `timestamptz` | NOT NULL  |
| `ends_at` | `timestamptz` | NOT NULL  |

Table constraints: `ends_at > starts_at`

### sale.deals
| Column | Type | Rules / meaning |
|---|---|---|
| `deal_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `sale_id` | `uuid` | NOT NULL REFERENCES sale.sales(sale_id)  |
| `sku` | `text` | NOT NULL Logical Product reference |
| `unit_price_minor` | `bigint` | NOT NULL  |
| `currency` | `char(3)` | NOT NULL  |

Table constraints: `unit_price_minor >= 0`; `UNIQUE (sale_id, sku)`

### sale.coupons
| Column | Type | Rules / meaning |
|---|---|---|
| `coupon_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `sale_id` | `uuid` | NOT NULL REFERENCES sale.sales(sale_id)  |
| `code` | `text` | NOT NULL UNIQUE  |
| `discount_minor` | `bigint` | NOT NULL  |
| `expires_at` | `timestamptz` | NOT NULL  |

Table constraints: `discount_minor >= 0`

### checkout.checkout_attempts
| Column | Type | Rules / meaning |
|---|---|---|
| `checkout_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `customer_id` | `text` | NOT NULL  |
| `status` | `text` | NOT NULL DEFAULT 'INITIATED'  |
| `reservation_id` | `uuid` | UNIQUE  |
| `payment_id` | `uuid` | UNIQUE  |
| `amount_minor` | `bigint` | NOT NULL  |
| `currency` | `char(3)` | NOT NULL  |
| `delivery_address` | `jsonb` | NOT NULL  |
| `next_retry_at` | `timestamptz` |   |
| `lease_until` | `timestamptz` |   |
| `version` | `bigint` | NOT NULL DEFAULT 0  |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `status IN ('INITIATED', 'RESERVING_INVENTORY', 'INVENTORY_RESERVED', 'PROCESSING_PAYMENT', 'AWAITING_PAYMENT_ACTION', 'PAYMENT_UNKNOWN', 'COMMITTING_INVENTORY', 'SUCCESS', 'FAILED_OUT_OF_STOCK', 'FAILED_PAYMENT_DECLINED', 'REFUND_PENDING', 'REFUNDED')`; `amount_minor > 0`; `jsonb_typeof(delivery_address) = 'object'`; `version >= 0`

### checkout.checkout_items
| Column | Type | Rules / meaning |
|---|---|---|
| `item_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `checkout_id` | `uuid` | NOT NULL REFERENCES checkout.checkout_attempts(checkout_id)  |
| `sku` | `text` | NOT NULL  |
| `quantity` | `integer` | NOT NULL  |
| `unit_price_minor` | `bigint` | NOT NULL  |

Table constraints: `quantity = 1`; `unit_price_minor > 0`; `UNIQUE (checkout_id)`

### inventory.inventory_items
| Column | Type | Rules / meaning |
|---|---|---|
| `sku` | `text` | PRIMARY KEY  |
| `total_stock` | `integer` | NOT NULL  |
| `available_stock` | `integer` | NOT NULL  |
| `reserved_stock` | `integer` | NOT NULL DEFAULT 0  |
| `sold_stock` | `integer` | NOT NULL DEFAULT 0  |
| `version` | `bigint` | NOT NULL DEFAULT 0  |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `total_stock >= 0`; `available_stock >= 0`; `reserved_stock >= 0`; `sold_stock >= 0`; `total_stock = available_stock + reserved_stock + sold_stock`; `version >= 0`

### inventory.reservations
| Column | Type | Rules / meaning |
|---|---|---|
| `reservation_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `checkout_id` | `uuid` | NOT NULL UNIQUE  |
| `sku` | `text` | NOT NULL REFERENCES inventory.inventory_items(sku)  |
| `quantity` | `integer` | NOT NULL  |
| `status` | `text` | NOT NULL DEFAULT 'HELD'  |
| `payment_id` | `uuid` | UNIQUE Bound only when committed; logical Payment reference |
| `expires_at` | `timestamptz` | NOT NULL  |
| `committed_at` | `timestamptz` |   |
| `release_reason` | `text` |   |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `quantity = 1`; `status IN ('HELD', 'COMMITTED', 'RELEASED', 'EXPIRED')`; `expires_at > created_at`; `(status = 'COMMITTED') = (payment_id IS NOT NULL AND committed_at IS NOT NULL)`

### payment.payment_transactions
| Column | Type | Rules / meaning |
|---|---|---|
| `payment_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `checkout_id` | `uuid` | NOT NULL UNIQUE  |
| `reservation_id` | `uuid` | NOT NULL UNIQUE  |
| `amount_minor` | `bigint` | NOT NULL  |
| `currency` | `char(3)` | NOT NULL  |
| `status` | `text` | NOT NULL DEFAULT 'INITIATED'  |
| `provider` | `text` | NOT NULL  |
| `provider_key` | `text` | NOT NULL  |
| `provider_reference` | `text` |   |
| `failure_code` | `text` |   |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `amount_minor > 0`; `status IN ('INITIATED', 'PENDING_3DS', 'AUTHORIZED', 'CAPTURED', 'UNKNOWN', 'DECLINED', 'FAILED', 'REFUNDED')`; `UNIQUE (provider, provider_key)`; `UNIQUE (provider, provider_reference)`

### payment.refunds
| Column | Type | Rules / meaning |
|---|---|---|
| `refund_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `payment_id` | `uuid` | NOT NULL UNIQUE REFERENCES payment.payment_transactions(payment_id)  |
| `amount_minor` | `bigint` | NOT NULL  |
| `status` | `text` | NOT NULL DEFAULT 'PENDING'  |
| `provider_key` | `text` | NOT NULL UNIQUE  |
| `provider_reference` | `text` | UNIQUE  |
| `reason` | `text` | NOT NULL  |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `amount_minor > 0`; `status IN ('PENDING', 'UNKNOWN', 'SUCCEEDED', 'FAILED')`

### payment.webhook_receipts
| Column | Type | Rules / meaning |
|---|---|---|
| `provider` | `text` | NOT NULL  |
| `provider_event_id` | `text` | NOT NULL  |
| `payload_hash` | `text` | NOT NULL  |
| `received_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (provider, provider_event_id)`

### orders.orders
| Column | Type | Rules / meaning |
|---|---|---|
| `order_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `checkout_id` | `uuid` | NOT NULL UNIQUE  |
| `customer_id` | `text` | NOT NULL  |
| `reservation_id` | `uuid` | NOT NULL UNIQUE  |
| `payment_id` | `uuid` | NOT NULL UNIQUE  |
| `status` | `text` | NOT NULL DEFAULT 'CONFIRMED'  |
| `amount_minor` | `bigint` | NOT NULL  |
| `currency` | `char(3)` | NOT NULL  |
| `delivery_address` | `jsonb` | NOT NULL  |
| `version` | `bigint` | NOT NULL DEFAULT 0  |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `amount_minor > 0`; `status IN ('CONFIRMED', 'PROCESSING', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'REFUNDED')`; `jsonb_typeof(delivery_address) = 'object'`; `version >= 0`

### orders.order_items
| Column | Type | Rules / meaning |
|---|---|---|
| `item_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `order_id` | `uuid` | NOT NULL REFERENCES orders.orders(order_id)  |
| `sku` | `text` | NOT NULL  |
| `quantity` | `integer` | NOT NULL  |
| `unit_price_minor` | `bigint` | NOT NULL  |

Table constraints: `quantity = 1`; `unit_price_minor > 0`; `UNIQUE (order_id)`

### fulfilment.shipments
| Column | Type | Rules / meaning |
|---|---|---|
| `shipment_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `order_id` | `uuid` | NOT NULL UNIQUE  |
| `carrier` | `text` |   |
| `tracking_number` | `text` |   |
| `status` | `text` | NOT NULL  |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `status IN ('PENDING', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED')`; `UNIQUE (carrier, tracking_number)`

### notification.notifications
| Column | Type | Rules / meaning |
|---|---|---|
| `notification_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `order_id` | `uuid` | NOT NULL  |
| `source_event_id` | `uuid` | NOT NULL  |
| `channel` | `text` | NOT NULL  |
| `recipient_reference` | `text` | NOT NULL  |
| `status` | `text` | NOT NULL  |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `UNIQUE (source_event_id, channel)`; `channel IN ('EMAIL', 'SMS')`; `status IN ('PENDING', 'SENT', 'FAILED')`

### checkout.idempotency_requests
| Column | Type | Rules / meaning |
|---|---|---|
| `caller_id` | `text` | NOT NULL  |
| `operation` | `text` | NOT NULL  |
| `idempotency_key` | `text` | NOT NULL  |
| `request_hash` | `text` | NOT NULL  |
| `resource_id` | `uuid` |   |
| `state` | `text` | NOT NULL  |
| `response_code` | `integer` |   |
| `response_body` | `jsonb` |   |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (caller_id, operation, idempotency_key)`; `state IN ('IN_PROGRESS', 'COMPLETED')`; `length(idempotency_key) BETWEEN 8 AND 128`; `state <> 'COMPLETED' OR (response_code IS NOT NULL AND response_body IS NOT NULL)`

### inventory.idempotency_requests
| Column | Type | Rules / meaning |
|---|---|---|
| `caller_id` | `text` | NOT NULL  |
| `operation` | `text` | NOT NULL  |
| `idempotency_key` | `text` | NOT NULL  |
| `request_hash` | `text` | NOT NULL  |
| `resource_id` | `uuid` |   |
| `state` | `text` | NOT NULL  |
| `response_code` | `integer` |   |
| `response_body` | `jsonb` |   |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (caller_id, operation, idempotency_key)`; `state IN ('IN_PROGRESS', 'COMPLETED')`; `length(idempotency_key) BETWEEN 8 AND 128`; `state <> 'COMPLETED' OR (response_code IS NOT NULL AND response_body IS NOT NULL)`

### payment.idempotency_requests
| Column | Type | Rules / meaning |
|---|---|---|
| `caller_id` | `text` | NOT NULL  |
| `operation` | `text` | NOT NULL  |
| `idempotency_key` | `text` | NOT NULL  |
| `request_hash` | `text` | NOT NULL  |
| `resource_id` | `uuid` |   |
| `state` | `text` | NOT NULL  |
| `response_code` | `integer` |   |
| `response_body` | `jsonb` |   |
| `created_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (caller_id, operation, idempotency_key)`; `state IN ('IN_PROGRESS', 'COMPLETED')`; `length(idempotency_key) BETWEEN 8 AND 128`; `state <> 'COMPLETED' OR (response_code IS NOT NULL AND response_body IS NOT NULL)`

### checkout.outbox_events
| Column | Type | Rules / meaning |
|---|---|---|
| `event_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `event_type` | `text` | NOT NULL  |
| `aggregate_id` | `text` | NOT NULL  |
| `aggregate_version` | `bigint` | NOT NULL  |
| `schema_version` | `integer` | NOT NULL DEFAULT 1  |
| `correlation_id` | `uuid` | NOT NULL  |
| `payload` | `jsonb` | NOT NULL  |
| `occurred_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `published_at` | `timestamptz` |   |
| `attempts` | `integer` | NOT NULL DEFAULT 0  |
| `next_attempt_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `lease_until` | `timestamptz` |   |

Table constraints: `UNIQUE (event_type, aggregate_id, aggregate_version)`; `aggregate_version >= 1`; `attempts >= 0`; `jsonb_typeof(payload) = 'object'`

### inventory.outbox_events
| Column | Type | Rules / meaning |
|---|---|---|
| `event_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `event_type` | `text` | NOT NULL  |
| `aggregate_id` | `text` | NOT NULL  |
| `aggregate_version` | `bigint` | NOT NULL  |
| `schema_version` | `integer` | NOT NULL DEFAULT 1  |
| `correlation_id` | `uuid` | NOT NULL  |
| `payload` | `jsonb` | NOT NULL  |
| `occurred_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `published_at` | `timestamptz` |   |
| `attempts` | `integer` | NOT NULL DEFAULT 0  |
| `next_attempt_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `lease_until` | `timestamptz` |   |

Table constraints: `UNIQUE (event_type, aggregate_id, aggregate_version)`; `aggregate_version >= 1`; `attempts >= 0`; `jsonb_typeof(payload) = 'object'`

### payment.outbox_events
| Column | Type | Rules / meaning |
|---|---|---|
| `event_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `event_type` | `text` | NOT NULL  |
| `aggregate_id` | `text` | NOT NULL  |
| `aggregate_version` | `bigint` | NOT NULL  |
| `schema_version` | `integer` | NOT NULL DEFAULT 1  |
| `correlation_id` | `uuid` | NOT NULL  |
| `payload` | `jsonb` | NOT NULL  |
| `occurred_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `published_at` | `timestamptz` |   |
| `attempts` | `integer` | NOT NULL DEFAULT 0  |
| `next_attempt_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `lease_until` | `timestamptz` |   |

Table constraints: `UNIQUE (event_type, aggregate_id, aggregate_version)`; `aggregate_version >= 1`; `attempts >= 0`; `jsonb_typeof(payload) = 'object'`

### orders.outbox_events
| Column | Type | Rules / meaning |
|---|---|---|
| `event_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `event_type` | `text` | NOT NULL  |
| `aggregate_id` | `text` | NOT NULL  |
| `aggregate_version` | `bigint` | NOT NULL  |
| `schema_version` | `integer` | NOT NULL DEFAULT 1  |
| `correlation_id` | `uuid` | NOT NULL  |
| `payload` | `jsonb` | NOT NULL  |
| `occurred_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `published_at` | `timestamptz` |   |
| `attempts` | `integer` | NOT NULL DEFAULT 0  |
| `next_attempt_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `lease_until` | `timestamptz` |   |

Table constraints: `UNIQUE (event_type, aggregate_id, aggregate_version)`; `aggregate_version >= 1`; `attempts >= 0`; `jsonb_typeof(payload) = 'object'`

### fulfilment.outbox_events
| Column | Type | Rules / meaning |
|---|---|---|
| `event_id` | `uuid` | PRIMARY KEY Application-generated UUID |
| `event_type` | `text` | NOT NULL  |
| `aggregate_id` | `text` | NOT NULL  |
| `aggregate_version` | `bigint` | NOT NULL  |
| `schema_version` | `integer` | NOT NULL DEFAULT 1  |
| `correlation_id` | `uuid` | NOT NULL  |
| `payload` | `jsonb` | NOT NULL  |
| `occurred_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `published_at` | `timestamptz` |   |
| `attempts` | `integer` | NOT NULL DEFAULT 0  |
| `next_attempt_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |
| `lease_until` | `timestamptz` |   |

Table constraints: `UNIQUE (event_type, aggregate_id, aggregate_version)`; `aggregate_version >= 1`; `attempts >= 0`; `jsonb_typeof(payload) = 'object'`

### inventory.processed_events
| Column | Type | Rules / meaning |
|---|---|---|
| `consumer_name` | `text` | NOT NULL  |
| `event_id` | `uuid` | NOT NULL  |
| `processed_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (consumer_name, event_id)`

### checkout.processed_events
| Column | Type | Rules / meaning |
|---|---|---|
| `consumer_name` | `text` | NOT NULL  |
| `event_id` | `uuid` | NOT NULL  |
| `processed_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (consumer_name, event_id)`

### orders.processed_events
| Column | Type | Rules / meaning |
|---|---|---|
| `consumer_name` | `text` | NOT NULL  |
| `event_id` | `uuid` | NOT NULL  |
| `processed_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (consumer_name, event_id)`

### fulfilment.processed_events
| Column | Type | Rules / meaning |
|---|---|---|
| `consumer_name` | `text` | NOT NULL  |
| `event_id` | `uuid` | NOT NULL  |
| `processed_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (consumer_name, event_id)`

### notification.processed_events
| Column | Type | Rules / meaning |
|---|---|---|
| `consumer_name` | `text` | NOT NULL  |
| `event_id` | `uuid` | NOT NULL  |
| `processed_at` | `timestamptz` | NOT NULL DEFAULT CURRENT_TIMESTAMP  |

Table constraints: `PRIMARY KEY (consumer_name, event_id)`

## Explicit indexes
```sql
CREATE INDEX reservations_expiry_idx ON inventory.reservations (expires_at) WHERE status = 'HELD';
CREATE INDEX checkout_recovery_idx ON checkout.checkout_attempts (next_retry_at, updated_at) WHERE status NOT IN ('SUCCESS','FAILED_OUT_OF_STOCK','FAILED_PAYMENT_DECLINED','REFUNDED');
CREATE INDEX payment_reconcile_idx ON payment.payment_transactions (updated_at) WHERE status IN ('INITIATED','PENDING_3DS','AUTHORIZED','UNKNOWN');
CREATE INDEX orders_customer_idx ON orders.orders (customer_id, created_at DESC);
CREATE INDEX product_category_idx ON product.products (category_id);
CREATE INDEX refunds_retry_idx ON payment.refunds (updated_at) WHERE status IN ('PENDING','UNKNOWN','FAILED');
CREATE INDEX checkout_outbox_pending_idx ON checkout.outbox_events (next_attempt_at, occurred_at) WHERE published_at IS NULL;
CREATE INDEX inventory_outbox_pending_idx ON inventory.outbox_events (next_attempt_at, occurred_at) WHERE published_at IS NULL;
CREATE INDEX payment_outbox_pending_idx ON payment.outbox_events (next_attempt_at, occurred_at) WHERE published_at IS NULL;
CREATE INDEX orders_outbox_pending_idx ON orders.outbox_events (next_attempt_at, occurred_at) WHERE published_at IS NULL;
CREATE INDEX fulfilment_outbox_pending_idx ON fulfilment.outbox_events (next_attempt_at, occurred_at) WHERE published_at IS NULL;
```
Primary keys and UNIQUE constraints provide indexes for their lookup keys. Foreign key lookup indexes are covered by unique constraints for one-item child tables or added explicitly.

## Application checks beyond SQL
Verify trusted price/currency, address shape, refund amount equals captured amount (full-refund demo), order total equals item total, legal state transitions and authenticated ownership. Cross-table stock/reservation equality requires transactional code and periodic audit; the single-row stock CHECK alone cannot prove it.

## Cart key-value contract
HLD retains an ephemeral cart store: key cart:{customer_id}, value {items:[{sku,quantity}],updated_at,version}. Proposed idle TTL 24 hours; a lost cart does not change inventory or payments. CartItem belongs to the cart value, not a separate SQL table. Checkout always reprices server-side. Limited-use coupon counters require their own reservation workflow; this demo uses eligibility/price rules only.
