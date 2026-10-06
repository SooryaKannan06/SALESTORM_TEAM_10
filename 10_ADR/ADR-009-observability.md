# Architecture Decision Record (ADR)
## ADR-009: OpenTelemetry Observability Stack, RED/USE Metrics, and WORM Audit Logging

---

### Status
**ACCEPTED**

### Context
Real-time operational visibility and forensic auditing are required during flash sales to detect stock balance anomalies, latency spikes, and system failures instantly.

---

### Decision
1. **OpenTelemetry Unified Telemetry**:
   - RED Metrics (Rate, Errors, Duration) for microservice HTTP endpoints in Prometheus.
   - USE Metrics (Utilization, Saturation, Errors) for infrastructure (CPU, Redis Memory, HikariCP DB pool).
   - Distributed Tracing: W3C TraceContext headers (`trace_id`, `span_id`) across Gateway, Microservices, and Kafka in Grafana Tempo.
2. **Alerting Rules**: Zero-delay alert for `salestorm_inventory_stock_balance < 0` or Kafka lag > 1000.
3. **WORM Immutable Audit**: Audit logs stored in AWS S3 Glacier Vault in Compliance Mode (Write Once Read Many) for 7-year immutable retention.

---

### Trade-offs & Consequences
- Provides instant diagnostic capability during live flash sale incidents.
- Guarantees regulatory compliance for security audit trails.
