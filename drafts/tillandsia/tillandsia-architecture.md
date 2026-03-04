# Tillandsia — Agent Orchestration over Matrix

**Status:** DRAFT — Review requested
**Date:** 2026-02-27
**Authors:** Liam Helmer, Bel

---

## 1. Overview

Tillandsia is an agent orchestration framework built on the Matrix protocol. Agents communicate, receive commands, deliver results, and obtain secrets through encrypted Matrix rooms. The system is designed for fail-closed security, ephemeral worker identities, and zero ambient credentials.

The name comes from air plants (Tillandsia) — organisms that attach to existing infrastructure and thrive without soil. Like them, agents attach to hosts and operate with nothing but their Matrix identity.

## 2. Principles

- **No ambient credentials.** Agents hold only their Matrix device keys. All other secrets are requested at runtime and scoped by identity.
- **Fail closed.** If the policy agent or secrets coordinator is down, agents cannot access rooms or obtain credentials. Work stops rather than proceeding unsafely.
- **Ephemeral by default.** Worker agents are created per-task and tombstoned after completion. Identities are disposable.
- **Auditable.** Every command, result, secret request, and policy decision is a signed event in a Matrix room DAG. Immutable, append-only, E2EE.
- **Host-agnostic.** A launcher runs anywhere — bare metal, VM, container, Pi, cloud instance. It just needs a network connection to the homeserver.

## 3. Components

### 3.1 Homeserver (Tuwunel)

The Matrix homeserver. All agents register here. Single source of truth for identity, room membership, and event history.

- **Implementation:** Tuwunel (Rust, embedded RocksDB, single binary)
- **Server name:** `tillandsia` (or `tillandsia.epiphytic.org` for federation)
- **OIDC:** Built-in OIDC server (PR #342 branch) with rich claims extension for external service federation

### 3.2 Policy Agent (Appservice)

A Matrix Application Service that enforces access control.

**Responsibilities:**
- Owns the `@agent-*:tillandsia` namespace exclusively
- Intercepts all events for agent users before delivery
- Checks policy rooms for authorization rules
- Grants/revokes room membership based on policy
- **Fail-closed:** If the appservice is down, the homeserver rejects events for the agent namespace

**Policy model:**
- Policies are stored as state events in dedicated policy rooms (MSC2313 pattern)
- The policy agent subscribes to these rooms and enforces rules in real-time
- Policy changes are auditable (they're Matrix events)

**Example policy room state:**
```json
{
  "type": "org.tillandsia.policy.agent_access",
  "state_key": "@launcher-belthanior:tillandsia",
  "content": {
    "spaces": ["!project-girt:tillandsia"],
    "rooms": ["#builds:tillandsia", "#deployments:tillandsia"],
    "power_level": 50,
    "can_spawn_workers": true,
    "allowed_commands": ["cargo", "git", "npm", "node"],
    "secret_scopes": ["github:Epiphytic/girt:*"]
  }
}
```

### 3.3 Orchestrator

A high-level agent (could be AI-driven or human-controlled) that plans and delegates work.

**Responsibilities:**
- Creates project spaces and rooms
- Invites leader agents to project rooms
- Sends commands to launchers
- Monitors worker progress via room events
- Makes placement decisions based on host telemetry

**The orchestrator does NOT:**
- Hold secrets (it requests them like any other agent if needed)
- Bypass the policy agent
- Directly execute work on hosts

### 3.4 Secrets Coordinator

A deterministic service with a Matrix client identity that brokers access to secrets.

**Responsibilities:**
- Receives secret requests as DMs from agents on its own homeserver
- Verifies the requesting agent's Matrix identity (E2EE provides cryptographic proof)
- Checks the agent's allowed secret scopes (via policy room or internal policy)
- For dynamic secrets: generates ephemeral credentials (e.g., GitHub tokens via octo-sts)
- For static secrets: decrypts from encrypted-at-rest store
- Returns secrets via E2EE DM to the requesting agent
- Logs all access events to an audit room

**Security constraints:**
- Only accepts DMs from agents on its own homeserver (verifies server_name in MXID)
- Verifies the requesting account is still active (not deactivated/tombstoned)
- Never stores secrets in Matrix rooms — secrets are in-memory or encrypted-at-rest
- Its own credentials (HSM keys, GitHub App key) never enter Matrix

See [Section 5: Secrets Architecture](#5-secrets-architecture) for full details.

### 3.5 Launcher

A minimal, persistent daemon running on a host machine. The "ear" on each host.

**Responsibilities:**
- Maintains a persistent Matrix identity (`@launcher-{hostname}:tillandsia`)
- Listens for commands in its dedicated execution room
- Executes allowed commands in isolated shells (one shell per UUID)
- Streams stdout/stderr as threaded replies to command events
- Spawns worker agents on demand
- Reports host telemetry (CPU, memory, disk, GPU, IOPs) periodically
- Grants the orchestrator access to its space
- Creates its own space for organizing rooms

**What it has:**
- Matrix device keys (its only credential)
- A configured allow-list of CLI commands and/or WASM modules
- The homeserver URL

**What it does NOT have:**
- Any secrets, tokens, or API keys
- Network access beyond the homeserver (ideally firewall-enforced)

**Execution model:**
```
Execution Room: #launcher-belthanior-exec:tillandsia
│
├── [orchestrator] org.tillandsia.command
│   uuid: "abc-123"
│   action: "exec"
│   cmd: "cargo build --release"
│   env: {"CARGO_HOME": "/tmp/cargo", "RUSTFLAGS": "-C target-cpu=native"}
│   cwd: "/workspace/girt"
│
│   ├── [launcher] THREAD org.tillandsia.output
│   │   uuid: "abc-123", stream: "stdout"
│   │   data: "   Compiling girt v0.1.0 (/workspace/girt)"
│   │
│   ├── [launcher] THREAD org.tillandsia.output
│   │   uuid: "abc-123", stream: "stderr"
│   │   data: "warning: unused import `std::io`"
│   │
│   └── [launcher] THREAD org.tillandsia.result
│       uuid: "abc-123", status: "exit", code: 0, duration_ms: 34200
```

**Telemetry model:**
```json
{
  "type": "org.tillandsia.host_telemetry",
  "state_key": "",
  "content": {
    "timestamp": "2026-02-27T15:30:00Z",
    "hostname": "belthanior",
    "cpu_percent": 42.3,
    "mem_used_gb": 12.1,
    "mem_total_gb": 32.0,
    "disk_used_percent": 67,
    "gpu": {
      "name": "RX 7900 XTX",
      "util_percent": 85,
      "vram_used_gb": 18.2,
      "vram_total_gb": 24.0
    },
    "iops": {"read": 1240, "write": 380},
    "load_avg": [2.1, 1.8, 1.5],
    "uptime_hours": 342
  }
}
```

Posted as a state event (always-current, overwritten) in the launcher's status room. Orchestrator reads these to make scheduling decisions.

**OpenTelemetry support:** The launcher can optionally export telemetry to external collectors (GCP Cloud Monitoring, Datadog, Grafana, etc.) in addition to Matrix. The Matrix telemetry is the universal baseline; external collectors are opt-in per deployment.

### 3.6 Worker Agents

Ephemeral agents spawned by launchers for specific tasks.

**Lifecycle:**
1. Launcher registers a new Matrix user: `@worker-{uuid}:tillandsia` (~55ms)
2. Worker logs in, initializes E2EE crypto (~75ms)
3. Worker joins its assigned room, exchanges keys (~30ms)
4. Worker requests any needed secrets from the Secrets Coordinator via DM
5. Worker executes its task (could be a Claude Code session, a build, a test run, etc.)
6. Worker posts results to its room
7. Worker account is **deactivated and tombstoned** — identity permanently retired

**Total spin-up to first E2EE message: ~155ms** (measured).

**After tombstoning:**
- All access tokens invalidated
- Device keys removed
- All rooms left
- MXID permanently retired (cannot be re-registered)
- Any late-arriving events for this user are rejected by the homeserver

## 4. Event Schema

### 4.1 Namespacing

All custom events use the `org.tillandsia.*` namespace:

| Event Type | Purpose |
|---|---|
| `org.tillandsia.command` | Command from orchestrator/leader to launcher |
| `org.tillandsia.output` | Stdout/stderr stream from execution |
| `org.tillandsia.result` | Exit status and summary of a command |
| `org.tillandsia.host_telemetry` | Host resource utilization (state event) |
| `org.tillandsia.secret_request` | Agent requesting a secret (DM) |
| `org.tillandsia.secret_response` | Coordinator delivering a secret (DM) |
| `org.tillandsia.worker_spawned` | Notification that a worker was created |
| `org.tillandsia.worker_tombstoned` | Notification that a worker was retired |
| `org.tillandsia.policy.agent_access` | Policy room: agent access rules (state event) |
| `org.tillandsia.policy.secret_scope` | Policy room: secret scope grants (state event) |

### 4.2 Command Event

```json
{
  "type": "org.tillandsia.command",
  "content": {
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "action": "exec | spawn_worker | install | update",
    "cmd": "cargo build --release",
    "args": ["--features", "gpu"],
    "env": {
      "CARGO_HOME": "/tmp/cargo",
      "RUST_LOG": "info"
    },
    "cwd": "/workspace/girt",
    "wasm_module": null,
    "allowed_commands": ["cargo", "git"],
    "timeout_seconds": 3600,
    "reply_room": null
  }
}
```

### 4.3 Output Event (threaded reply)

```json
{
  "type": "org.tillandsia.output",
  "content": {
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "stream": "stdout | stderr",
    "data": "Compiling girt v0.1.0...",
    "seq": 42,
    "timestamp": "2026-02-27T15:30:01.234Z"
  },
  "m.relates_to": {
    "rel_type": "m.thread",
    "event_id": "$command_event_id"
  }
}
```

### 4.4 Result Event (threaded reply)

```json
{
  "type": "org.tillandsia.result",
  "content": {
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "status": "exit | killed | timeout | error",
    "exit_code": 0,
    "duration_ms": 34200,
    "output_lines": 847,
    "summary": "Build succeeded"
  },
  "m.relates_to": {
    "rel_type": "m.thread",
    "event_id": "$command_event_id"
  }
}
```

### 4.5 Secret Request (DM)

```json
{
  "type": "org.tillandsia.secret_request",
  "content": {
    "request_id": "req-001",
    "scope": "github:Epiphytic/girt:contents:read",
    "ttl_seconds": 3600,
    "reason": "Need to clone repo for build task abc-123"
  }
}
```

### 4.6 Secret Response (DM)

```json
{
  "type": "org.tillandsia.secret_response",
  "content": {
    "request_id": "req-001",
    "granted": true,
    "secret_type": "bearer_token",
    "value": "ghs_xxxxxxxxxxxx",
    "expires_at": "2026-02-27T16:30:00Z",
    "scope": "github:Epiphytic/girt:contents:read"
  }
}
```

## 5. Secrets Architecture

### 5.1 Design Goals

- No secrets stored on agent hosts (only Matrix device keys)
- Secrets scoped by Matrix identity — the coordinator checks who is asking, not what they claim to need
- Dynamic secrets preferred over static (short-lived > long-lived)
- HSM support for the coordinator's own key material
- Full audit trail of every secret access

### 5.2 Secret Types

| Type | Generation | Storage | Example |
|---|---|---|---|
| **Dynamic (STS)** | Generated on demand via token exchange | Never stored — created and delivered | GitHub tokens (octo-sts), GCP access tokens, AWS STS |
| **Static (encrypted)** | Pre-provisioned by admin | Encrypted at rest, decrypted in-memory by coordinator | API keys, webhook secrets, database passwords |
| **Derived** | Computed from other secrets + context | Never stored | HMAC signatures, scoped tokens |

### 5.3 Secrets Coordinator Architecture

```
┌────────────────────────────────────────────────┐
│           Secrets Coordinator Process           │
│                                                │
│  ┌──────────────┐  ┌────────────────────────┐  │
│  │ Matrix Client │  │    Secret Backends     │  │
│  │              │  │                        │  │
│  │  Receives    │  │  ┌─────────────────┐   │  │
│  │  DMs         │──│──│  Dynamic (STS)  │   │  │
│  │  Verifies    │  │  │  - octo-sts     │   │  │
│  │  identity    │  │  │  - GCP WIF      │   │  │
│  │  Checks      │  │  │  - AWS STS      │   │  │
│  │  policy      │  │  └─────────────────┘   │  │
│  │  Returns     │  │                        │  │
│  │  via E2EE DM │  │  ┌─────────────────┐   │  │
│  │              │  │  │  Static Store   │   │  │
│  └──────────────┘  │  │  (age-encrypted │   │  │
│                    │  │   + HSM key)    │   │  │
│                    │  └─────────────────┘   │  │
│                    │                        │  │
│                    │  ┌─────────────────┐   │  │
│                    │  │  HSM / KMS      │   │  │
│                    │  │  (PKCS#11 or    │   │  │
│                    │  │   cloud KMS)    │   │  │
│                    │  └─────────────────┘   │  │
│                    └────────────────────────┘  │
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │           Audit Logger                   │  │
│  │  Posts to #secrets-audit:tillandsia      │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

### 5.4 Request Flow

```
1. Worker @worker-abc:tillandsia sends E2EE DM to @secrets:tillandsia:
   → org.tillandsia.secret_request { scope: "github:Epiphytic/girt:contents:read" }

2. Coordinator receives DM. Verifies:
   a. Sender is on same homeserver (server_name == "tillandsia")
   b. Sender account is active (not deactivated)
   c. Sender's MXID matches an allowed pattern in policy room
   d. Requested scope is within sender's allowed scopes

3. If denied:
   → org.tillandsia.secret_response { granted: false, reason: "scope not authorized" }
   → Audit event posted to #secrets-audit

4. If approved (dynamic secret):
   a. Coordinator calls octo-sts with its own GitHub App credentials
   b. octo-sts returns ephemeral GitHub token (scoped, short-lived)
   c. Coordinator returns token via E2EE DM
   d. Audit event posted

5. If approved (static secret):
   a. Coordinator looks up secret in its encrypted store
   b. Decrypts using HSM-backed key (PKCS#11 unwrap, or cloud KMS decrypt)
   c. Returns value via E2EE DM
   d. Audit event posted
```

### 5.5 Static Secret Storage

**Encryption at rest:**
- Secrets stored as an `age`-encrypted file on the coordinator's host
- The `age` identity (private key) is either:
  - Stored in an HSM (PKCS#11) — **preferred for production**
  - Wrapped by a cloud KMS key (GCP/AWS) — **good for cloud deployments**
  - Stored as a file readable only by the coordinator process — **acceptable for dev/home**
- On startup, coordinator decrypts the store into memory
- Memory is locked (mlock) to prevent swapping to disk

**Access tiers:**
- **Write-only:** Admin user DMs coordinator to add/update secrets. Coordinator re-encrypts the store.
- **Read-only:** Agents request secrets via DM. Coordinator serves from memory.
- **Admin:** Human operator with access to the raw encrypted file and HSM credentials. Can rotate the encryption key, export/import secrets.

**Secret rotation:**
- Dynamic secrets rotate automatically (every STS call = new token)
- Static secrets: coordinator can be told to rotate via admin command
- The coordinator tracks which agents received which secrets. On rotation, it can notify active agents that their secret has changed.

### 5.6 HSM Integration

The coordinator's own key material (GitHub App private key, age identity, signing keys) must be protected by hardware security:

**Option A: PKCS#11 HSM (on-premise)**
- YubiHSM 2, Nitrokey HSM, or SoftHSM for development
- Coordinator uses PKCS#11 interface to unwrap/sign
- Private keys never leave the HSM
- Suitable for: belthanior, on-premise deployments

**Option B: Cloud KMS (cloud deployments)**
- GCP Cloud KMS, AWS KMS, Azure Key Vault
- Coordinator calls KMS API to decrypt the secret store encryption key
- KMS key never leaves the cloud provider's HSM
- Suitable for: GCP/AWS deployments, Liam's work environment

**Option C: TPM (host-bound)**
- Use the host's TPM 2.0 to seal the coordinator's key material
- Key is bound to the specific hardware + software state
- Suitable for: dedicated hardware, high-security deployments

For development/home use, SoftHSM with PKCS#11 gives the same API surface as a real HSM, so the code is production-ready from day one.

### 5.7 Threat Model

| Threat | Mitigation |
|---|---|
| Compromised worker requests unauthorized secrets | Policy check on every request; scopes enforced per-identity |
| Compromised homeserver reads secrets in transit | E2EE (Megolm) — homeserver cannot decrypt DM content |
| Late messages to tombstoned worker | Coordinator checks account is active before responding |
| Federated user spoofs local MXID | Coordinator strictly checks server_name portion of MXID |
| Coordinator process compromise | HSM protects key material; secrets in memory only (mlock'd) |
| Coordinator host compromise | HSM keys require physical presence / cloud IAM; blast radius = static secrets in memory |
| Replay of secret_response events | Secrets have TTL; coordinator tracks issued secrets and can revoke |
| Admin user compromise | Require 2FA for admin commands; dual-control for high-value secrets |

### 5.8 What This Does NOT Solve

- **Homeserver availability** — if Tuwunel is down, nothing works. Federation and redundancy address this separately.
- **Agent code integrity** — a launcher executes what it's told. If the orchestrator is compromised, it can send malicious commands. Code signing / WASM verification could address this (future work, possibly via GIRT).
- **Network-level isolation** — Matrix messages transit the network. TLS protects the wire; E2EE protects the content. But traffic analysis is possible.

## 6. Room Topology

```
Space: Tillandsia Infrastructure
├── #policy:tillandsia              — Policy rules (state events)
├── #secrets-audit:tillandsia       — Audit log of all secret access
├── #orchestrator-control:tillandsia — Orchestrator commands/status
│
├── Space: Launchers
│   ├── Space: launcher-belthanior
│   │   ├── #launcher-belthanior-exec:tillandsia   — Command execution
│   │   ├── #launcher-belthanior-status:tillandsia  — Telemetry (state events)
│   │   └── #launcher-belthanior-logs:tillandsia    — System logs
│   │
│   └── Space: launcher-pi-farm
│       ├── #launcher-pi-farm-exec:tillandsia
│       ├── #launcher-pi-farm-status:tillandsia
│       └── #launcher-pi-farm-logs:tillandsia
│
└── Space: Projects
    ├── Space: project-girt
    │   ├── #girt-builds:tillandsia
    │   ├── #girt-tests:tillandsia
    │   └── #girt-deploys:tillandsia
    │
    └── Space: project-voice
        ├── #voice-builds:tillandsia
        └── #voice-tests:tillandsia
```

## 7. Implementation Phases

### Phase 1: Foundation (Current)
- [x] Tuwunel homeserver running
- [x] E2EE agent clients (matrix-sdk-crypto-wasm)
- [x] Draupnir moderation bot
- [x] Policy enforcement testing
- [x] Performance benchmarks (155ms registration, 7ms E2EE round-trip)
- [ ] OIDC branch with rich claims
- [ ] Benchmark comparison (baseline vs rich claims)

### Phase 2: Policy Agent
- [ ] Matrix Appservice skeleton (Node.js or Rust)
- [ ] Exclusive namespace registration for `@agent-*:tillandsia`
- [ ] Policy room subscription and enforcement
- [ ] Fail-closed verification tests

### Phase 3: Launcher
- [ ] Minimal daemon (Node.js initially, Rust later)
- [ ] Matrix client with auto-reconnect
- [ ] Command execution with UUID threading
- [ ] Stdout/stderr streaming as room events
- [ ] Allow-list enforcement (CLI commands + WASM)
- [ ] Host telemetry reporting
- [ ] Worker spawning

### Phase 4: Secrets Coordinator
- [ ] Matrix client with DM handling
- [ ] Identity verification (same-homeserver, active account)
- [ ] Policy-based scope checking
- [ ] octo-sts integration (GitHub dynamic tokens)
- [ ] age-encrypted static secret store
- [ ] HSM integration (PKCS#11 / SoftHSM for dev)
- [ ] Audit logging to dedicated room

### Phase 5: Orchestrator
- [ ] Project space/room creation
- [ ] Agent invitation and role assignment
- [ ] Placement decisions based on host telemetry
- [ ] Task tracking via room events
- [ ] Integration with existing tools (GIRT, CI/CD)

### Phase 6: Production Hardening
- [ ] Federation support (multi-homeserver)
- [ ] Cloud KMS integration
- [ ] WASM module verification
- [ ] Rate limiting and abuse prevention
- [ ] Monitoring and alerting
- [ ] Disaster recovery procedures

## 8. Performance Baseline

Measured on belthanior (AMD Ryzen, 32GB RAM, Tuwunel local):

| Operation | Latency |
|---|---|
| Agent registration | 53ms |
| Login | 21ms |
| Crypto init (OlmMachine) | 36ms |
| E2EE key exchange | 25ms |
| **Registration → first E2EE message** | **155ms** |
| E2EE send (encrypt + PUT) | 1.8ms p50 |
| E2EE receive (sync + decrypt) | 4.2ms p50 |
| **E2EE round-trip** | **6.0ms p50** |
| OIDC discovery | 0.10ms p50 |
| OIDC userinfo | 0.18ms p50 |
| JWKS fetch | 0.09ms p50 |

## 9. Open Questions

1. **Launcher language:** Node.js (fast to build, matrix-sdk-crypto-wasm works) vs Rust (smaller binary, better for constrained devices like Pi). Could start Node.js and port to Rust.

2. **WASM execution in launcher:** Use GIRT's runtime, wasmtime directly, or something else? GIRT already has a WASM pipeline with security review.

3. **Orchestrator intelligence:** Human-driven (Liam sends commands), AI-driven (Claude/GPT plans work), or hybrid? The architecture supports all three.

4. **Federation scope:** When does this need to work across homeservers? That changes the secrets model (cross-homeserver DMs for secrets require more trust verification).

5. **Secret lease management:** Should the coordinator actively revoke secrets after TTL, or just refuse to re-issue? Active revocation requires knowing how the secret is being used (can't revoke a GitHub token without calling GitHub's API).

---

*This document is a living draft. Update as architecture decisions are made.*
