# SALESTORM — Module 4: Concurrency & Reliability Architecture
## Document 08: Horizontal Scaling & Capacity Planning

---

### 1. Scaling Strategy Overview

To transition smoothly from **Normal Operations (~10,000 req/sec)** to **Flash Sale Peak (up to 500,000 req/sec)**, the SALESTORM platform employs horizontal scaling across every infrastructure tier. All application services are engineered to be 100% stateless, pushing state exclusively into high-throughput clustered infrastructure stores (Redis Cluster, Apache Kafka, PostgreSQL Aurora).

```
[ Flash Sale Traffic Peak: 500,000 req/sec ]
                     |
                     v
+-------------------------------------------------------+
| Edge Layer: Envoy / NGINX Ingress Cluster (Auto-Scale)|
+-------------------------------------------------------+
                     |
                     v
+-------------------------------------------------------+
| App Layer: Stateless Microservices (Kubernetes HPA)   |
| - API Gateway: 10 -> 80 Pods                          |
| - Inventory Service: 15 -> 120 Pods                   |
| - Payment Service: 10 -> 60 Pods                      |
+-------------------------------------------------------+
                     |
          +----------+----------+
          |                     |
          v                     v
+------------------+  +----------------------------------+
| Redis Cluster    |  | Database Layer                   |
| - 16 Master Nodes|  | - PostgreSQL Primary (Writes)    |
| - 16 Read Slaves |  | - PgBouncer Pooler (5,000 conns) |
| - Hash Slot Shard|  | - 4 Read Replicas (Reads)        |
+------------------+  +----------------------------------+
```

---

### 2. Kubernetes Horizontal Pod Autoscaler (HPA) Policy

Microservices scale dynamically based on custom metrics (Kafka Consumer Lag, Request Rate) in addition to CPU and Memory utilization.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: inventory-service-hpa
  namespace: salestorm
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: inventory-service
  minReplicas: 15
  maxReplicas: 120
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
  - type: External
    external:
      metric:
        name: kafka_consumergroup_lag
      target:
        type: Value
        averageValue: "500"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100 # Double pod count instantly on flash sale start
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300 # Prevent premature downscaling
```

---

### 3. Redis Cluster Partitioning & Sharding Strategy

To process up to 500,000 req/sec across flash sale items:

1. **Topology**: 16 Master Nodes + 16 Replica Nodes.
2. **Memory Throughput Capacity**: Single Redis master node achieves ~80,000 atomic Lua executions/sec. 16 master nodes yield **> 1,200,000 ops/sec capacity**.
3. **Hot-Spot Item Distribution**: High-demand products are allocated across distinct cluster hash slots using product-specific hash keys:

$$\text{Key Format}: \text{salestorm:}\{product\_id\}:\text{stock}$$

- `salestorm:{prod_1001}:stock` -> Slot 4312 (Master Node 1)
- `salestorm:{prod_1002}:stock` -> Slot 9120 (Master Node 4)
- `salestorm:{prod_1003}:stock` -> Slot 14201 (Master Node 12)

---

### 4. Database Tier Scaling & Connection Pooling (PgBouncer)

Direct application connections to PostgreSQL under 120 auto-scaled pods would quickly exceed database connection limits ($120 \text{ pods} \times 50 \text{ connections} = 6,000 \text{ connections}$), causing kernel context switching overhead.

SALESTORM introduces **PgBouncer Connection Poolers** operating in `transaction` mode:

```
120 Inventory Service Pods (6,000 App Threads)
                  |
                  v
[ PgBouncer Connection Pool Cluster ] (Transaction Pooling)
                  |  Max Active Server Conns = 250
                  v
[ PostgreSQL Primary Database Node ]
```

- **PgBouncer Mode**: Transaction Pooling. Connection is multiplexed and returned to pool immediately upon `COMMIT` or `ROLLBACK`.
- **Read/Write Splitting**: Non-transactional queries (`GET /orders/history`, catalog browsing) are offloaded to **4 PostgreSQL Read Replicas** via reader endpoint routing.

---

### 5. Infrastructure Sizing & Capacity Planning Summary

| Component Layer | Normal Operations (10k req/s) | Flash Sale Peak (500k req/s) | Scaling Trigger |
| :--- | :--- | :--- | :--- |
| **Envoy API Gateway** | 6 Pods (4 vCPU, 8GB) | 80 Pods (8 vCPU, 16GB) | CPU > 60% / RPS > 15k |
| **Inventory Microservice**| 15 Pods (2 vCPU, 4GB) | 120 Pods (4 vCPU, 8GB) | CPU > 65% / Kafka Lag |
| **Redis Cluster Nodes** | 6 Masters (16GB RAM) | 16 Masters (32GB RAM) | Memory / IOPS Pre-provision |
| **PgBouncer Poolers** | 2 Nodes (4 vCPU) | 8 Nodes (8 vCPU) | Connection saturation |
| **Kafka Broker Cluster** | 3 Brokers (NVMe Storage) | 7 Brokers (NVMe Storage)| Write Throughput > 50MB/s |
