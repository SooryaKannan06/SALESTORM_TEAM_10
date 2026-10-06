# SALESTORM — Prometheus Alert Rules Configuration

---

## Prometheus Alert Rules Specification

```yaml
groups:
- name: salestorm_reliability_alerts
  rules:

  # CRITICAL ALERT: Immediate Oversell Alert
  - alert: InventoryOversoldDetected
    expr: salestorm_inventory_stock_balance < 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "CRITICAL: Stock balance became negative!"

  # WARNING ALERT: High API 5xx Error Rate
  - alert: HighAPIErrorRate
    expr: (sum(rate(salestorm_http_requests_total{status=~"5.."}[2m])) / sum(rate(salestorm_http_requests_total[2m]))) * 100 > 5
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "High API Error Rate (> 5%)"

  # WARNING ALERT: Kafka Consumer Group Lag
  - alert: KafkaConsumerLagHigh
    expr: sum(kafka_consumergroup_lag{consumergroup="order-service-group"}) > 1000
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Order Service Kafka Lag > 1000 messages"
```
