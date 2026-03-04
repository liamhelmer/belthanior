# Multi-Home Identity & Regional Resilience

**Status:** DRAFT
**Date:** 2026-03-02
**Supersedes:** Single-homeserver model in tillandsia-architecture.md §3.1

---

## 1. Problem

A single homeserver is a single point of failure. If `home.tillandsia.epiphytic.org` goes down:
- No agent can log in
- No agent can sync
- No commands can be sent or received
- The entire system stops

Matrix federation replicates room data across homeservers, but it doesn't solve **client login** — an agent registered on `home` can't authenticate against `us-west1` with its `home` credentials.

## 2. Solution: Multi-Home Agents

Every agent client maintains **parallel registrations** across all configured homeservers. Each registration is a separate Matrix identity, but the system treats them as one logical entity.

```
Logical Identity: "launcher-belthanior"

Registrations:
  @launcher-belthanior:home       ← home.tillandsia.epiphytic.org
  @launcher-belthanior:us-west1   ← us-west1.tillandsia.epiphytic.org
  @launcher-belthanior:eu-west1   ← eu-west1.tillandsia.epiphytic.org

All three MXIDs:
  - Are cross-signed (cryptographic proof of same entity)
  - Have identical privileges in the policy system
  - Are members of the same federated rooms
  - Share the same logical identity prefix
```

### 2.1 How Rooms Work

All operational rooms are **federated across all homeservers**. This happens naturally in Matrix — when `@launcher-belthanior:home` and `@launcher-belthanior:us-west1` both join `#girt-builds:home`, the room state is replicated to both `home` and `us-west1` servers.

**Key design choice:** Essential communication happens in **rooms, not DMs**. This is because:
- All registrations of a client join the same rooms
- Any registration can read events from any other federated server
- If one homeserver goes down, the room still exists on the others
- The client reads from whichever connection is healthy
- **Duplicate execution prevention:** The client sees the same room events from all connections. It deduplicates based on event ID (globally unique in Matrix). A command posted once in a federated room is seen once, regardless of how many connections the client has.

### 2.2 Failover Model

```
Normal operation:
  Client ←→ home (primary)
  Client ←→ us-west1 (active standby)
  Client ←→ eu-west1 (active standby)
  
  All connections active. Client syncs from all.
  Sends via primary (fastest/healthiest).
  Deduplicates incoming events by event_id.

home goes down:
  Client ←✗→ home (connection lost)
  Client ←→ us-west1 (promoted to primary)
  Client ←→ eu-west1 (active standby)
  
  Client continues operating via us-west1 identity.
  Federated rooms still have full event history.
  New events posted from @launcher-belthanior:us-west1.
  Other agents see same logical identity (cross-signed).
  
home comes back:
  Client ←→ home (reconnected, federation catches up)
  Client ←→ us-west1
  Client ←→ eu-west1
  
  Federation syncs any events that occurred during downtime.
  Client resumes using primary connection.
```

### 2.3 Connection Health

The client continuously monitors connection health:

```typescript
interface HomeserverConnection {
  url: string;
  serverName: string;           // "home", "us-west1", etc.
  mxid: string;                 // "@launcher-belthanior:home"
  status: 'healthy' | 'degraded' | 'down';
  latencyMs: number;            // rolling average from /sync
  lastSync: Date;
  priority: number;             // lower = preferred for sending
}
```

The client picks the healthiest connection for outbound events. Inbound events are received from all healthy connections and deduplicated.

## 3. Identity Binding

### 3.1 Cross-Signing

Each registration cross-signs the device keys of all other registrations. This creates a cryptographic chain proving that all MXIDs belong to the same entity.

```
@launcher-belthanior:home
  └── device key: Ed25519:AAAAAA
      └── cross-signs: @launcher-belthanior:us-west1 / Ed25519:BBBBBB
      └── cross-signs: @launcher-belthanior:eu-west1 / Ed25519:CCCCCC

@launcher-belthanior:us-west1
  └── device key: Ed25519:BBBBBB
      └── cross-signs: @launcher-belthanior:home / Ed25519:AAAAAA
      └── cross-signs: @launcher-belthanior:eu-west1 / Ed25519:CCCCCC

@launcher-belthanior:eu-west1
  └── device key: Ed25519:CCCCCC
      └── cross-signs: @launcher-belthanior:home / Ed25519:AAAAAA
      └── cross-signs: @launcher-belthanior:us-west1 / Ed25519:BBBBBB
```

**Verification flow:** When Agent B receives a message from `@launcher-belthanior:us-west1` and has previously verified `@launcher-belthanior:home`, it can follow the cross-signing chain to trust the us-west1 identity without additional human intervention.

### 3.2 Identity Binding Event

In addition to cross-signing (which is per-device), the client publishes an **identity binding** state event to a well-known room:

```json
{
  "type": "org.tillandsia.identity_binding",
  "state_key": "launcher-belthanior",
  "content": {
    "logical_id": "launcher-belthanior",
    "registrations": [
      {
        "mxid": "@launcher-belthanior:home",
        "server_name": "home",
        "homeserver": "https://home.tillandsia.epiphytic.org",
        "device_id": "AAAAAA",
        "device_key": "Ed25519:...",
        "registered_at": "2026-03-01T00:00:00Z"
      },
      {
        "mxid": "@launcher-belthanior:us-west1",
        "server_name": "us-west1",
        "homeserver": "https://us-west1.tillandsia.epiphytic.org",
        "device_id": "BBBBBB",
        "device_key": "Ed25519:...",
        "registered_at": "2026-03-01T00:00:00Z"
      }
    ],
    "cross_signatures": {
      "AAAAAA→BBBBBB": "base64sig...",
      "BBBBBB→AAAAAA": "base64sig..."
    },
    "updated_at": "2026-03-01T00:00:00Z"
  }
}
```

This state event lives in the `#identity-registry:home` room (federated). Any agent can verify identity bindings by:
1. Reading the identity binding event
2. Verifying the cross-signatures against the published device keys
3. Trusting that all listed MXIDs are the same entity

### 3.3 Policy Resolution

The Policy Agent resolves privileges by logical identity, not by MXID:

```
Input:  Who is @launcher-belthanior:us-west1?
Step 1: Look up identity_binding for prefix "launcher-belthanior"
Step 2: Verify cross-signatures (cryptographic proof)
Step 3: Resolve policy for logical_id "launcher-belthanior"
Result: Same privileges as @launcher-belthanior:home
```

Policy rules reference logical IDs:

```json
{
  "type": "org.tillandsia.policy.agent_access",
  "state_key": "launcher-belthanior",
  "content": {
    "logical_id": "launcher-belthanior",
    "spaces": ["!project-girt:home"],
    "secret_scopes": ["github:Epiphytic/girt:*"],
    "can_spawn_workers": true
  }
}
```

Not:

```json
"state_key": "@launcher-belthanior:home"  // ← wrong, would break on failover
```

## 4. Client Architecture Update

```
@tillandsia/client
│
├── MultiHomeManager
│   ├── connections: HomeserverConnection[]
│   ├── primaryConnection: HomeserverConnection
│   │
│   ├── register(logicalId, homeservers[])
│   │   → registers on each homeserver
│   │   → cross-signs all device keys
│   │   → publishes identity_binding event
│   │
│   ├── send(roomId, event)
│   │   → picks healthiest connection
│   │   → sends via that connection's identity
│   │
│   ├── sync()
│   │   → syncs from ALL connections in parallel
│   │   → deduplicates by event_id
│   │   → emits unified event stream
│   │
│   └── healthCheck()
│       → pings all connections
│       → promotes/demotes primary based on latency
│
├── IdentityManager
│   ├── crossSign(deviceA, deviceB)
│   ├── publishBinding(logicalId, registrations[])
│   └── verifyBinding(logicalId) → bool
│
└── EventDeduplicator
    ├── seen: Set<eventId>
    └── isDuplicate(event) → bool
```

## 5. Secrets Coordinator Update

The Secrets Coordinator must accept requests from any registration of a logical identity:

```
Request from: @launcher-belthanior:us-west1
Step 1: Extract prefix: "launcher-belthanior"
Step 2: Verify identity_binding (cross-signatures valid?)
Step 3: Check policy for logical_id "launcher-belthanior"
Step 4: If authorized → deliver secret via E2EE DM to the requesting MXID
```

**Important:** The coordinator still only accepts requests from agents on **configured homeservers** (not arbitrary federated servers). The allow-list is now a list of homeserver server_names, not a single one:

```toml
[secrets]
allowed_homeservers = ["home", "us-west1", "eu-west1"]
```

## 6. Worker Agents in Multi-Home

Workers are ephemeral and short-lived. They do NOT need multi-home resilience — they exist for a single task on a single homeserver. If that homeserver goes down during the task, the task fails and can be retried.

Workers register on the **same homeserver as their parent launcher's current primary connection**. This minimizes latency and keeps the worker close to the launcher.

```
Launcher (logical: launcher-belthanior)
  └── currently primary on: us-west1
      └── spawns worker: @worker-abc:us-west1
          └── single registration, single homeserver
          └── task completes → tombstoned
```

If the launcher fails over mid-task, the worker on the old homeserver may become unreachable. The launcher detects this and can spawn a replacement worker on the new primary homeserver.

## 7. Federation Tuning

For quick sync across regions, Tuwunel should be configured for aggressive federation:

```toml
[global]
# Federation settings for low-latency sync
federation_timeout = 5          # seconds, fail fast
federation_idle_timeout = 30    # keep connections warm
federation_max_concurrent_requests = 50

# Retry quickly
federation_retry_initial = 1    # 1 second initial retry
federation_retry_max = 30       # cap at 30 seconds
```

**Expected federation latency:**
- Same region (e.g., two servers in us-west1): <10ms
- Cross-region (e.g., us-west1 ↔ eu-west1): ~100-150ms (network RTT)
- Home (Vancouver) ↔ GCP us-west1 (Oregon): ~20-30ms

With eventual consistency accepted, these latencies are fine. A command sent on `home` will appear on `us-west1` within ~50ms including federation processing.

## 8. Registration Bootstrapping

When a new agent client starts for the first time:

```
1. Client has: logical_id, registration_token, list of homeserver URLs
2. For each homeserver:
   a. Register @{logical_id}:{server_name} using registration token
   b. Login, get access_token + device_id
   c. Init OlmMachine (generate device keys)
   d. Upload device keys
3. Cross-sign all device keys pairwise
4. Publish identity_binding event to #identity-registry:{primary}
5. Join all required rooms from each connection
6. Begin parallel sync from all connections
7. Ready.
```

**Estimated bootstrap time** (3 homeservers):
- Registration × 3: ~160ms (parallel)
- Crypto init × 3: ~120ms (parallel)
- Cross-signing (3 pairs): ~50ms
- Identity binding publish: ~5ms
- Room joins: ~20ms per room
- **Total: ~400ms** to be fully multi-homed and operational

## 9. Edge Cases

### 9.1 Split Brain

Two homeservers can't reach each other but both are reachable by agents. Events accumulate independently. When federation resumes, Matrix's DAG merge resolves the fork — all events from both sides become visible, ordered by their DAG position.

**For commands:** A command posted on `home` during a split won't be seen by a launcher connected only to `us-west1`. The launcher should monitor for gaps (missing sequence numbers or time gaps) and alert the orchestrator.

### 9.2 Identity Binding Conflicts

If someone registers `@launcher-belthanior:rogue-server` and tries to claim the identity, the cross-signing verification fails — they can't produce valid signatures from the legitimate device keys. The Policy Agent rejects unverified bindings.

### 9.3 Homeserver Permanently Lost

If a homeserver is permanently decommissioned:
1. Remove it from the identity_binding event
2. Revoke the device keys for that registration
3. Update the client configuration
4. Other registrations continue operating

---

*This document extends the base architecture. Read alongside tillandsia-architecture.md.*
