BEGIN;

CREATE SCHEMA IF NOT EXISTS checkout;

CREATE SCHEMA IF NOT EXISTS fulfilment;

CREATE SCHEMA IF NOT EXISTS inventory;

CREATE SCHEMA IF NOT EXISTS notification;

CREATE SCHEMA IF NOT EXISTS orders;

CREATE SCHEMA IF NOT EXISTS payment;

CREATE SCHEMA IF NOT EXISTS product;

CREATE SCHEMA IF NOT EXISTS sale;

CREATE TABLE product.categories (
    category_id uuid PRIMARY KEY,
    name text NOT NULL UNIQUE
);

CREATE TABLE product.products (
    product_id uuid PRIMARY KEY,
    category_id uuid NOT NULL REFERENCES product.categories(category_id),
    sku text NOT NULL UNIQUE,
    name text NOT NULL,
    unit_price_minor bigint NOT NULL,
    currency char(3) NOT NULL DEFAULT 'INR',
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (unit_price_minor >= 0)
);

CREATE TABLE sale.sales (
    sale_id uuid PRIMARY KEY,
    name text NOT NULL,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    CHECK (ends_at > starts_at)
);

CREATE TABLE sale.deals (
    deal_id uuid PRIMARY KEY,
    sale_id uuid NOT NULL REFERENCES sale.sales(sale_id),
    sku text NOT NULL,
    unit_price_minor bigint NOT NULL,
    currency char(3) NOT NULL,
    CHECK (unit_price_minor >= 0),
    UNIQUE (sale_id, sku)
);

CREATE TABLE sale.coupons (
    coupon_id uuid PRIMARY KEY,
    sale_id uuid NOT NULL REFERENCES sale.sales(sale_id),
    code text NOT NULL UNIQUE,
    discount_minor bigint NOT NULL,
    expires_at timestamptz NOT NULL,
    CHECK (discount_minor >= 0)
);

CREATE TABLE checkout.checkout_attempts (
    checkout_id uuid PRIMARY KEY,
    customer_id text NOT NULL,
    status text NOT NULL DEFAULT 'INITIATED',
    reservation_id uuid UNIQUE,
    payment_id uuid UNIQUE,
    amount_minor bigint NOT NULL,
    currency char(3) NOT NULL,
    delivery_address jsonb NOT NULL,
    next_retry_at timestamptz,
    lease_until timestamptz,
    version bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (status IN ('INITIATED', 'RESERVING_INVENTORY', 'INVENTORY_RESERVED', 'PROCESSING_PAYMENT', 'AWAITING_PAYMENT_ACTION', 'PAYMENT_UNKNOWN', 'COMMITTING_INVENTORY', 'SUCCESS', 'FAILED_OUT_OF_STOCK', 'FAILED_PAYMENT_DECLINED', 'REFUND_PENDING', 'REFUNDED')),
    CHECK (amount_minor > 0),
    CHECK (jsonb_typeof(delivery_address) = 'object'),
    CHECK (version >= 0)
);

CREATE TABLE checkout.checkout_items (
    item_id uuid PRIMARY KEY,
    checkout_id uuid NOT NULL REFERENCES checkout.checkout_attempts(checkout_id),
    sku text NOT NULL,
    quantity integer NOT NULL,
    unit_price_minor bigint NOT NULL,
    CHECK (quantity = 1),
    CHECK (unit_price_minor > 0),
    UNIQUE (checkout_id)
);

CREATE TABLE inventory.inventory_items (
    sku text PRIMARY KEY,
    total_stock integer NOT NULL,
    available_stock integer NOT NULL,
    reserved_stock integer NOT NULL DEFAULT 0,
    sold_stock integer NOT NULL DEFAULT 0,
    version bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (total_stock >= 0),
    CHECK (available_stock >= 0),
    CHECK (reserved_stock >= 0),
    CHECK (sold_stock >= 0),
    CHECK (total_stock = available_stock + reserved_stock + sold_stock),
    CHECK (version >= 0)
);

CREATE TABLE inventory.reservations (
    reservation_id uuid PRIMARY KEY,
    checkout_id uuid NOT NULL UNIQUE,
    sku text NOT NULL REFERENCES inventory.inventory_items(sku),
    quantity integer NOT NULL,
    status text NOT NULL DEFAULT 'HELD',
    payment_id uuid UNIQUE,
    expires_at timestamptz NOT NULL,
    committed_at timestamptz,
    release_reason text,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (quantity = 1),
    CHECK (status IN ('HELD', 'COMMITTED', 'RELEASED', 'EXPIRED')),
    CHECK (expires_at > created_at),
    CHECK ((status = 'COMMITTED') = (payment_id IS NOT NULL AND committed_at IS NOT NULL))
);

CREATE TABLE payment.payment_transactions (
    payment_id uuid PRIMARY KEY,
    checkout_id uuid NOT NULL UNIQUE,
    reservation_id uuid NOT NULL UNIQUE,
    amount_minor bigint NOT NULL,
    currency char(3) NOT NULL,
    status text NOT NULL DEFAULT 'INITIATED',
    provider text NOT NULL,
    provider_key text NOT NULL,
    provider_reference text,
    failure_code text,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (amount_minor > 0),
    CHECK (status IN ('INITIATED', 'PENDING_3DS', 'AUTHORIZED', 'CAPTURED', 'UNKNOWN', 'DECLINED', 'FAILED', 'REFUNDED')),
    UNIQUE (provider, provider_key),
    UNIQUE (provider, provider_reference)
);

CREATE TABLE payment.refunds (
    refund_id uuid PRIMARY KEY,
    payment_id uuid NOT NULL UNIQUE REFERENCES payment.payment_transactions(payment_id),
    amount_minor bigint NOT NULL,
    status text NOT NULL DEFAULT 'PENDING',
    provider_key text NOT NULL UNIQUE,
    provider_reference text UNIQUE,
    reason text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (amount_minor > 0),
    CHECK (status IN ('PENDING', 'UNKNOWN', 'SUCCEEDED', 'FAILED'))
);

CREATE TABLE payment.webhook_receipts (
    provider text NOT NULL,
    provider_event_id text NOT NULL,
    payload_hash text NOT NULL,
    received_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (provider, provider_event_id)
);

CREATE TABLE orders.orders (
    order_id uuid PRIMARY KEY,
    checkout_id uuid NOT NULL UNIQUE,
    customer_id text NOT NULL,
    reservation_id uuid NOT NULL UNIQUE,
    payment_id uuid NOT NULL UNIQUE,
    status text NOT NULL DEFAULT 'CONFIRMED',
    amount_minor bigint NOT NULL,
    currency char(3) NOT NULL,
    delivery_address jsonb NOT NULL,
    version bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (amount_minor > 0),
    CHECK (status IN ('CONFIRMED', 'PROCESSING', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'REFUNDED')),
    CHECK (jsonb_typeof(delivery_address) = 'object'),
    CHECK (version >= 0)
);

CREATE TABLE orders.order_items (
    item_id uuid PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES orders.orders(order_id),
    sku text NOT NULL,
    quantity integer NOT NULL,
    unit_price_minor bigint NOT NULL,
    CHECK (quantity = 1),
    CHECK (unit_price_minor > 0),
    UNIQUE (order_id)
);

CREATE TABLE fulfilment.shipments (
    shipment_id uuid PRIMARY KEY,
    order_id uuid NOT NULL UNIQUE,
    carrier text,
    tracking_number text,
    status text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (status IN ('PENDING', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED')),
    UNIQUE (carrier, tracking_number)
);

CREATE TABLE notification.notifications (
    notification_id uuid PRIMARY KEY,
    order_id uuid NOT NULL,
    source_event_id uuid NOT NULL,
    channel text NOT NULL,
    recipient_reference text NOT NULL,
    status text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (source_event_id, channel),
    CHECK (channel IN ('EMAIL', 'SMS')),
    CHECK (status IN ('PENDING', 'SENT', 'FAILED'))
);

CREATE TABLE checkout.idempotency_requests (
    caller_id text NOT NULL,
    operation text NOT NULL,
    idempotency_key text NOT NULL,
    request_hash text NOT NULL,
    resource_id uuid,
    state text NOT NULL,
    response_code integer,
    response_body jsonb,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (caller_id, operation, idempotency_key),
    CHECK (state IN ('IN_PROGRESS', 'COMPLETED')),
    CHECK (length(idempotency_key) BETWEEN 8 AND 128),
    CHECK (state <> 'COMPLETED' OR (response_code IS NOT NULL AND response_body IS NOT NULL))
);

CREATE TABLE inventory.idempotency_requests (
    caller_id text NOT NULL,
    operation text NOT NULL,
    idempotency_key text NOT NULL,
    request_hash text NOT NULL,
    resource_id uuid,
    state text NOT NULL,
    response_code integer,
    response_body jsonb,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (caller_id, operation, idempotency_key),
    CHECK (state IN ('IN_PROGRESS', 'COMPLETED')),
    CHECK (length(idempotency_key) BETWEEN 8 AND 128),
    CHECK (state <> 'COMPLETED' OR (response_code IS NOT NULL AND response_body IS NOT NULL))
);

CREATE TABLE payment.idempotency_requests (
    caller_id text NOT NULL,
    operation text NOT NULL,
    idempotency_key text NOT NULL,
    request_hash text NOT NULL,
    resource_id uuid,
    state text NOT NULL,
    response_code integer,
    response_body jsonb,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (caller_id, operation, idempotency_key),
    CHECK (state IN ('IN_PROGRESS', 'COMPLETED')),
    CHECK (length(idempotency_key) BETWEEN 8 AND 128),
    CHECK (state <> 'COMPLETED' OR (response_code IS NOT NULL AND response_body IS NOT NULL))
);

CREATE TABLE checkout.outbox_events (
    event_id uuid PRIMARY KEY,
    event_type text NOT NULL,
    aggregate_id text NOT NULL,
    aggregate_version bigint NOT NULL,
    schema_version integer NOT NULL DEFAULT 1,
    correlation_id uuid NOT NULL,
    payload jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at timestamptz,
    attempts integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lease_until timestamptz,
    UNIQUE (event_type, aggregate_id, aggregate_version),
    CHECK (aggregate_version >= 1),
    CHECK (attempts >= 0),
    CHECK (jsonb_typeof(payload) = 'object')
);

CREATE TABLE inventory.outbox_events (
    event_id uuid PRIMARY KEY,
    event_type text NOT NULL,
    aggregate_id text NOT NULL,
    aggregate_version bigint NOT NULL,
    schema_version integer NOT NULL DEFAULT 1,
    correlation_id uuid NOT NULL,
    payload jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at timestamptz,
    attempts integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lease_until timestamptz,
    UNIQUE (event_type, aggregate_id, aggregate_version),
    CHECK (aggregate_version >= 1),
    CHECK (attempts >= 0),
    CHECK (jsonb_typeof(payload) = 'object')
);

CREATE TABLE payment.outbox_events (
    event_id uuid PRIMARY KEY,
    event_type text NOT NULL,
    aggregate_id text NOT NULL,
    aggregate_version bigint NOT NULL,
    schema_version integer NOT NULL DEFAULT 1,
    correlation_id uuid NOT NULL,
    payload jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at timestamptz,
    attempts integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lease_until timestamptz,
    UNIQUE (event_type, aggregate_id, aggregate_version),
    CHECK (aggregate_version >= 1),
    CHECK (attempts >= 0),
    CHECK (jsonb_typeof(payload) = 'object')
);

CREATE TABLE orders.outbox_events (
    event_id uuid PRIMARY KEY,
    event_type text NOT NULL,
    aggregate_id text NOT NULL,
    aggregate_version bigint NOT NULL,
    schema_version integer NOT NULL DEFAULT 1,
    correlation_id uuid NOT NULL,
    payload jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at timestamptz,
    attempts integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lease_until timestamptz,
    UNIQUE (event_type, aggregate_id, aggregate_version),
    CHECK (aggregate_version >= 1),
    CHECK (attempts >= 0),
    CHECK (jsonb_typeof(payload) = 'object')
);

CREATE TABLE fulfilment.outbox_events (
    event_id uuid PRIMARY KEY,
    event_type text NOT NULL,
    aggregate_id text NOT NULL,
    aggregate_version bigint NOT NULL,
    schema_version integer NOT NULL DEFAULT 1,
    correlation_id uuid NOT NULL,
    payload jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at timestamptz,
    attempts integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lease_until timestamptz,
    UNIQUE (event_type, aggregate_id, aggregate_version),
    CHECK (aggregate_version >= 1),
    CHECK (attempts >= 0),
    CHECK (jsonb_typeof(payload) = 'object')
);

CREATE TABLE inventory.processed_events (
    consumer_name text NOT NULL,
    event_id uuid NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (consumer_name, event_id)
);

CREATE TABLE checkout.processed_events (
    consumer_name text NOT NULL,
    event_id uuid NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (consumer_name, event_id)
);

CREATE TABLE orders.processed_events (
    consumer_name text NOT NULL,
    event_id uuid NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (consumer_name, event_id)
);

CREATE TABLE fulfilment.processed_events (
    consumer_name text NOT NULL,
    event_id uuid NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (consumer_name, event_id)
);

CREATE TABLE notification.processed_events (
    consumer_name text NOT NULL,
    event_id uuid NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (consumer_name, event_id)
);

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

COMMIT;
