# SALESTORM — Security Architecture & Threat Model Overview

---

## 1. Multi-Layer Security Model

SALESTORM adopts a **4-Layer Defense-in-Depth Security Model**:

```
[ Web / Mobile Clients ]
           |
           v
+-------------------------------------------------------+
| LAYER 1: Cloudflare WAF & Edge Rate Limiter          | -> Bot defense, DDoS mitigation, TLS 1.3
+-------------------------------------------------------+
           |
           v
+-------------------------------------------------------+
| LAYER 2: API Gateway Identity & Token Verification    | -> OAuth2 + JWT (RSA256 Signature Check)
+-------------------------------------------------------+
           |
           v
+-------------------------------------------------------+
| LAYER 3: Microservice Service Mesh (Istio mTLS)       | -> Pod-to-pod identity & encrypted transport
+-------------------------------------------------------+
           |
           v
+-------------------------------------------------------+
| LAYER 4: Database Storage & WORM Audit Storage        | -> AES-256 Envelope Encryption, S3 Glacier WORM
+-------------------------------------------------------+
```

---

## 2. Core Security Principles
- **Least Privilege**: Microservices operate under restricted IAM roles and RBAC OAuth2 scopes.
- **Zero Trust Network**: Every pod-to-pod RPC requires Mutual TLS (mTLS) with SPIFFE identity validation.
- **No Sensitive PII in Logs**: Automatic LogSanitizer scrubs credit card tokens, auth headers, and emails prior to log ingestion.
