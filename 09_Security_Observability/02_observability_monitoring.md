# SALESTORM — Module 4: Security & Observability Architecture
## Document 02: Observability Architecture, Metrics, Tracing & Alerting

---

### 1. Observability Stack Architecture

During high-concurrency flash sales, real-time observability is the difference between diagnosing an issue in seconds versus suffering catastrophic outages. SALESTORM deploys an **OpenTelemetry-native Observability Stack**:

```
+-----------------------------------------------------------------------------------+
|                           MICROSERVICE PODS & PROXIES                             |
|  [ API Gateway ]      [ Inventory Svc ]      [ Payment Svc ]      [ Order Svc ]   |
|         |                     |                     |                    |        |
|  OpenTelemetry SDK     OpenTelemetry SDK     OpenTelemetry SDK    OpenTelemetry SDK|
+-----------------------------------------------------------------------------------+
       | (Metrics)                   | (Traces)                   | (Logs)
       v                             v                            v
+------------------+        +------------------+        +-------------------+
| Prometheus Server|        | Jaeger / Tempo   |        | Grafana Loki      |
| (Pull Collector) |        | (Trace Collector)|        | (Log Aggregation) |
+------------------+        +------------------+        +-------------------+
        \                            |                           /
         \                           v                          /
          +----------------> [ Grafana Dashboards ] <----------+
                                     |
                                     v
                        [ Alertmanager / PagerDuty ]
```

---

### 2. Metrics Strategy: RED & USE Frameworks

#### 2.1 RED Metrics (Service Level - Application Tier)
- **Rate**: Number of HTTP/gRPC requests processed per second (`salestorm_http_requests_total`).
- **Errors**: Number of failed requests returning 5xx or unexpected 4xx status (`salestorm_http_requests_failed_total`).
- **Duration**: Latency distribution histograms (`salestorm_http_request_duration_seconds_bucket`).

#### 2.2 USE Metrics (Infrastructure Tier)
- **Utilization**: Percentage of time a resource is busy (CPU %, Memory %, Redis Memory %).
- **Saturation**: Queued work waiting to be processed (HikariCP DB Wait Queue, Kafka Consumer Group Lag, Redis Client Buffer).
- **Errors**: Count of error events (DB connection drop, Redis OOM, TCP socket resets).

---

### 3. Distributed Tracing Standard (W3C Trace Context)

Every incoming HTTP request at the API Gateway is injected with a **W3C Trace Context Header**:

$$\text{traceparent}: 00\text{-}4bf92f3577b34da6a3ce929d0e0e4736\text{-}00f067aa0ba902b7\text{-}01$$

```
[ Client Request ]
       |
       v
[ API Gateway ] --------------> trace_id: 4bf92f35... span_id: 0001
       |
       v
[ Inventory Service ] --------> trace_id: 4bf92f35... span_id: 0002 (parent: 0001)
       |
       +---> [ Redis Lua ] ---> trace_id: 4bf92f35... span_id: 0003 (parent: 0002)
       |
       v
[ Payment Service ] ----------> trace_id: 4bf92f35... span_id: 0004 (parent: 0001)
       |
       v
[ External Gateway ] ---------> trace_id: 4bf92f35... span_id: 0005 (parent: 0004)
```

**Benefit**: Complete end-to-end trace visualization across microservices in Jaeger/Tempo with exact sub-millisecond latency breakdown for every span.

---

### 4. Critical Prometheus Alert Rules

```yaml
groups:
- name: salestorm_reliability_alerts
  rules:

  # ALERT 1: Immediate Oversell Detection Alert (CRITICAL)
  - alert: InventoryOversoldDetected
    expr: salestorm_inventory_stock_balance < 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "CRITICAL: Inventory stock balance became negative!"
      description: "Product {{ $labels.product_id }} stock balance is {{ $value }}. Immediate intervention required."

  # ALERT 2: High API Error Rate
  - alert: HighAPIErrorRate
    expr: (sum(rate(salestorm_http_requests_total{status=~"5.."}[2m])) / sum(rate(salestorm_http_requests_total[2m]))) * 100 > 5
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "High API 5xx Error Rate (> 5%)"
      description: "Current error rate is {{ $value }}% over the last 2 minutes."

  # ALERT 3: Redis P99 Latency Spike
  - alert: RedisLuaLatencySpike
    expr: histogram_quantile(0.99, sum(rate(salestorm_redis_command_duration_seconds_bucket[2m])) by (le)) > 0.05
    for: 30s
    labels:
      severity: warning
    annotations:
      summary: "Redis P99 Latency > 50ms"
      description: "Redis Lua execution P99 latency is {{ $value }}s."

  # ALERT 4: Kafka Consumer Group Lag
  - alert: KafkaConsumerLagHigh
    expr: sum(kafka_consumergroup_lag{consumergroup="order-service-group"}) > 1000
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Order Service Kafka Lag > 1000 messages"
      description: "Order processing consumer lag is {{ $value }} messages."
```

---

### 5. Grafana Dashboard Specifications

The primary **SALESTORM Flash Sale Command Center** Grafana dashboard includes:
1. **Live Stock Gauge**: Visual real-time balance counter for Product X (100 -> 0).
2. **Concurrent User RPS Panel**: Incoming edge traffic split by Authorized, Rate Limited (429), and Sold Out (409).
3. **P99 Latency Heatmap**: Latency distribution broken down by Gateway, Inventory Lua, Payment, and Order Service.
4. **Idempotency Hit Rate Metric**: Percentage of duplicate requests caught cleanly by Redis locks.
5. **Kafka Queue Health**: Real-time consumer lag graphs per microservice topic.
