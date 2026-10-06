# SALESTORM — Payment Security & PCI-DSS Compliance

---

## 1. Zero Raw Card Data Guarantee

SALESTORM microservices **NEVER store, process, or transmit raw credit card numbers (PAN) or CVV values**.

### Client-Side Tokenization Flow
1. User enters payment details inside a client-side Stripe/Adyen iframe SDK.
2. Payment provider returns an ephemeral single-use Payment Token (`tok_stripe_99812`).
3. SALESTORM API receives only the token reference (`tok_stripe_99812`) for charge execution.

---

## 2. Payment Idempotency & Webhook Verification
- All payment webhooks carry an HMAC-SHA256 signature header (`X-Signature`) verified against a secret key stored in HashiCorp Vault.
- Payment Service verifies payment token uniqueness to prevent double-charging.
