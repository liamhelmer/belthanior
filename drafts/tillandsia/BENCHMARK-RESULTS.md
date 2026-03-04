# E2EE Latency Benchmark Results

**Date:** 2026-02-27
**Homeserver:** Tuwunel (Conduwuit fork) v1.5.0, single-node, localhost
**Agents:** 12 concurrent E2EE clients (matrix-sdk-crypto-wasm)
**Messages per pattern:** 500
**Runtime:** Node.js v22.22.0

## Purpose

Measure end-to-end encrypted message delivery latency on Tuwunel, comparing:

1. **Baseline** binary (standard Tuwunel, no OIDC rich claims)
2. **Rich Claims** binary (with `device_id`, `urn:matrix:admin`, `urn:matrix:rooms`, `urn:matrix:power_levels`, `urn:matrix:policy_scopes` claims added to the OIDC server)

The goal is to determine whether the rich claims implementation introduces any measurable overhead to E2EE message delivery.

---

## Methodology

### Patterns tested

| Pattern | Description |
|---------|-------------|
| **1:1 DMs** | 6 pairs of agents, ~84 messages each (504 total), alternating sender/receiver |
| **Group Room** | 12 agents in one room, 500 messages round-robin, measure delivery to next agent |
| **Fan-out** | 1 sender, 11 recipients in one room, 500 messages, measure delivery to all recipients |

### Metrics (per message)

- **Send latency**: Time to encrypt + HTTP PUT to homeserver
- **Delivery latency**: Time from send completion until recipient decrypts the message (via /sync polling)
- **Total E2E latency**: Send + delivery combined
- **Key exchange latency**: Time to establish Megolm sessions for all room members

### Measurement approach

Sequential poll-based measurement: send one message, then poll receiver(s) via /sync until the encrypted event arrives and is successfully decrypted. This avoids OlmMachine concurrency issues and gives clean per-message timing.

---

## Results Summary

### Total E2E Latency (encrypt + deliver + decrypt)

| Pattern | Metric | Baseline | Rich Claims | Delta |
|---------|--------|----------|-------------|-------|
| **1:1 DM** | p50 | 5.66ms | 4.00ms | -1.66ms (-29%) |
| | p95 | 7.94ms | 7.14ms | -0.80ms (-10%) |
| | p99 | 9.35ms | 8.65ms | -0.70ms (-7%) |
| | avg | 5.59ms | 4.37ms | -1.22ms (-22%) |
| **Group Room** | p50 | 6.97ms | 5.00ms | -1.97ms (-28%) |
| | p95 | 9.30ms | 7.57ms | -1.73ms (-19%) |
| | p99 | 10.50ms | 9.10ms | -1.40ms (-13%) |
| | avg | 7.01ms | 5.30ms | -1.71ms (-24%) |
| **Fan-out (last)** | p50 | 46.35ms | 37.93ms | -8.42ms (-18%) |
| | p95 | 54.49ms | 47.01ms | -7.48ms (-14%) |
| | p99 | 60.95ms | 51.12ms | -9.83ms (-16%) |
| | avg | 45.93ms | 38.65ms | -7.28ms (-16%) |

### Send Latency (encrypt + HTTP PUT)

| Pattern | Metric | Baseline | Rich Claims | Delta |
|---------|--------|----------|-------------|-------|
| **1:1 DM** | p50 | 1.67ms | 1.23ms | -0.44ms |
| | avg | 1.67ms | 1.37ms | -0.30ms |
| **Group Room** | p50 | 2.29ms | 1.92ms | -0.37ms |
| | avg | 2.42ms | 1.91ms | -0.51ms |
| **Fan-out** | p50 | 2.76ms | 1.92ms | -0.84ms |
| | avg | 2.94ms | 2.03ms | -0.91ms |

### Delivery Latency (send completion -> recipient decrypts)

| Pattern | Metric | Baseline | Rich Claims | Delta |
|---------|--------|----------|-------------|-------|
| **1:1 DM** | p50 | 4.01ms | 2.71ms | -1.30ms |
| | avg | 3.92ms | 3.00ms | -0.92ms |
| **Group Room** | p50 | 4.64ms | 3.06ms | -1.58ms |
| | avg | 4.58ms | 3.38ms | -1.20ms |
| **Fan-out (first)** | p50 | 3.83ms | 3.10ms | -0.73ms |
| | avg | 3.87ms | 3.34ms | -0.53ms |
| **Fan-out (last)** | p50 | 43.74ms | 35.82ms | -7.92ms |
| | avg | 42.99ms | 36.62ms | -6.37ms |

### Agent Lifecycle

| Metric | Baseline | Rich Claims |
|--------|----------|-------------|
| **Spin-up** avg | 47.01ms | 40.86ms |
| **Spin-up** p95 | 96.16ms | 93.84ms |
| **Key exchange (DM)** avg | 21.54ms | 17.37ms |
| **Key exchange (Group, 12 agents)** | 30,507ms | 30,412ms |
| **Teardown** avg | 0.34ms | 0.33ms |

---

## Analysis

### Key finding: No measurable overhead from rich claims

The rich claims binary showed **equal or better** latency across all patterns and all percentiles. The differences are within the range of normal run-to-run variance on a shared machine (the rich claims run benefited from warmer OS/RocksDB caches since it ran second).

The rich claims code paths (`/_tuwunel/oidc/userinfo`, token endpoint enrichment) are **only invoked during OIDC authentication flows**, not during:
- `/sync` polling
- Room event sending (`PUT /send`)
- Key upload/query/claim operations
- To-device message delivery

Since E2EE message delivery uses only the standard Matrix Client-Server API (not OIDC), the rich claims additions have **zero impact on the E2EE hot path**.

### Latency breakdown

For 1:1 DMs, the typical message lifecycle on localhost:
- ~1.3-1.7ms: client-side Megolm encrypt + HTTP PUT to homeserver
- ~2.7-4.0ms: /sync poll returns encrypted event + client-side decrypt
- **~4-6ms total** end-to-end

For fan-out (1 sender, 11 recipients):
- ~2-3ms: encrypt + send
- ~3ms: first recipient receives via /sync
- ~36-44ms: last of 11 recipients receives (sequential polling adds ~3-4ms per recipient)
- **~38-46ms total** to last recipient

### Group key exchange

The 12-agent group key exchange takes ~30.4s in both cases. This is dominated by the O(n^2) key claim/share pattern (each agent must establish Olm sessions with all 11 others, then share Megolm keys). This is an inherent property of the Matrix E2EE protocol, not a server-side bottleneck.

---

## Rich Claims Implementation

The following OIDC claims were added to the Tuwunel server:

### ID Token Claims
- `device_id` -- The Matrix device ID associated with the OIDC session
- `urn:matrix:admin` -- Boolean, present only when user is a server admin

### Userinfo Endpoint Claims
All of the above, plus:
- `urn:matrix:rooms` -- Array of joined rooms (capped at 100) with room_id, name, and canonical_alias
- `urn:matrix:power_levels` -- Object mapping room_id to the user's power level
- `urn:matrix:policy_scopes` -- Array of policy rules (m.policy.rule.user) that match the user

### Verification

The OIDC discovery document (`/.well-known/openid-configuration`) confirms all claims are advertised:
```json
"claims_supported": [
  "iss", "sub", "aud", "exp", "iat", "nonce",
  "device_id",
  "urn:matrix:admin",
  "urn:matrix:rooms",
  "urn:matrix:power_levels",
  "urn:matrix:policy_scopes"
]
```

---

## Environment Details

| Component | Version/Config |
|-----------|---------------|
| Tuwunel | v1.5.0, single-node, RocksDB backend |
| Server | `tillandsia` (localhost:8008) |
| Database | `/home/openclaw/matrix/tuwunel-data` |
| Node.js | v22.22.0 |
| Crypto | @matrix-org/matrix-sdk-crypto-wasm (OlmMachine) |
| Algorithm | m.megolm.v1.aes-sha2, rotation at 10,000 messages |
| Message size | Random 50-200 char text bodies |

---

## Raw Data

- Baseline: [`benchmark-e2ee-baseline.json`](./benchmark-e2ee-baseline.json)
- Rich Claims: [`benchmark-e2ee-richclaims.json`](./benchmark-e2ee-richclaims.json)
- Benchmark script: [`tillandsia-client/benchmark-e2ee.mjs`](./tillandsia-client/benchmark-e2ee.mjs)
