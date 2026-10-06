# SALESTORM — API Rate Limiting & Bot Protection

---

## 1. Rate Limiting Rules

API Gateway enforces multi-tier Redis Token Bucket rate limits:
- **Anonymous Requests**: 10 requests / second per IP address.
- **Authenticated Users**: 30 requests / second per User ID.
- **Excess Traffic Response**: HTTP 429 Too Many Requests with `Retry-After: 2` header.

---

## 2. Bot Scalping & Proof-of-Work Defense

1. **Proof-of-Work (PoW) Challenge**: Users entering the Virtual Waiting Room solve a browser SHA-256 CPU challenge (~300ms execution time) to prevent automated script scalping.
2. **IP Velocity Check**: Rejects >3 purchase attempts within 10 seconds from identical ASN subnets.
