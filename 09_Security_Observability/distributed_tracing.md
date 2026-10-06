# SALESTORM — Distributed Tracing (W3C Trace Context)

---

## 1. Trace Context Propagation

Every incoming request at Envoy API Gateway receives a **W3C TraceContext header**:
`traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`

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
```

---

## 2. Diagnostic Capability

Distributed tracing in Grafana Tempo / Jaeger pinpoint exact latency breakdowns across microservices:
- Identifies whether slow checkouts are caused by external payment gateway network delays, Kafka queue ingestion lag, or Redis cluster network round-trips.
