# SALESTORM — Authentication & Authorization Architecture

---

## 1. OAuth2 / JWT Identity Tokens

All API requests entering the platform must carry a signed JWT token in the HTTP header: `Authorization: Bearer <JWT_TOKEN>`.

### JWT Claims Schema
```json
{
  "iss": "https://auth.salestorm.io",
  "sub": "usr_9981245",
  "aud": "api.salestorm.io",
  "exp": 1769938900,
  "iat": 1769938000,
  "jti": "jwt_nonce_7781a",
  "roles": ["CUSTOMER"],
  "scope": "reservation:create payment:execute"
}
```

---

## 2. API Gateway Validation Engine

1. Envoy Proxy verifies JWT signature using RSA-256 Public Key (fetched via JWKS endpoint, cached in memory).
2. Checks expiration (`exp > now()`).
3. Rejects revoked tokens via Redis JWT Blacklist (`salestorm:jwt_blacklist:<jti>`).
4. Injects validated user identity header into upstream microservices: `X-User-ID: usr_9981245`.
