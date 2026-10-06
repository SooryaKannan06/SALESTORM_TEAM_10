# Architecture Decision Record (ADR)
## ADR-007: Horizontal Scaling & Virtual Waiting Room Admission Control Strategy

---

### Status
**ACCEPTED**

### Context
Flash sales generate extreme traffic spikes (design target up to 500,000 requests/sec at edge). Passing 500k req/sec directly to core reservation microservices when only 100 stock items exist will collapse backend databases and application pods.

---

### Decision
1. **Layered Traffic Admission Control**:
   - Cloudflare Edge WAF / Rate Limiter sheds bot flood.
   - API Gateway enforces per-user Token Bucket rate limits.
   - Virtual Waiting Room (VWR) holds excess users in a Redis Sorted Set queue and admits controlled batches based on downstream capacity.
2. **Stateless Service Autoscaling**: Microservices scale horizontally on Kubernetes HPA based on CPU/Memory and Kafka consumer lag metrics.
3. **Database Connection Protection**: PgBouncer multiplexes application connections down to safe server limits.

---

### Trade-offs & Consequences
- Protects downstream microservices and databases from thundering herd crashes.
- Users receive transparent waiting room queue positions instead of cryptic 500 server errors.
