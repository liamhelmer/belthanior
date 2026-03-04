# Tillandsia — Project Plan

**Status:** DRAFT — Review requested
**Date:** 2026-03-01
**Authors:** Liam Helmer, Bel

---

## 1. What We're Building

Tillandsia is an agent orchestration platform that uses Matrix as an encrypted, authenticated message bus. It consists of:

1. **A cross-platform agent client** (npm package + Rust/WASM core)
2. **A web control app** (Rust/HTMX, with Android PWA)
3. **Infrastructure tooling** (multi-region Tuwunel install, Terraform for GCP, CI/CD)

This is NOT a chat app. It's a command-and-control system for AI agents and automated workers that happens to use the Matrix protocol for identity, encryption, and transport.

---

## 2. Deliverables

### 2.1 `@tillandsia/client` — The Agent Client (npm package)

A single, minimalist client used by all node types: workers, launchers, orchestrators, secrets coordinators. Same package, different configuration.

**Architecture:**
```
@tillandsia/client (npm)
├── core/          ← Rust → WASM (compiled via wasm-pack)
│   ├── crypto     ← matrix-sdk-crypto (Rust, not the JS wrapper)
│   ├── protocol   ← org.tillandsia.* event parsing/validation
│   ├── identity   ← registration, login, device management, deactivation
│   └── policy     ← sender verification, event filtering, allowlists
│
├── transport/     ← TypeScript
│   ├── sync       ← filtered /sync long-polling (only org.tillandsia.* events)
│   ├── send       ← encrypted event sending
│   ├── to-device  ← secret request/response DMs
│   └── http       ← minimal Matrix CS API wrapper (7 endpoints)
│
├── roles/         ← TypeScript, role-specific behavior
│   ├── launcher   ← command execution, stdout/stderr streaming, telemetry
│   ├── worker     ← ephemeral task execution, auto-teardown
│   ├── orchestrator ← space/room management, task dispatch, placement
│   └── secrets    ← secret request/response, HSM integration hooks
│
└── index.ts       ← TillandsiaClient class, role-based configuration
```

**Why Rust/WASM for core:**
- matrix-sdk-crypto (Rust) is the canonical implementation — same code as Element uses, audited, complete
- No dependency on the JS WASM wrapper (@matrix-org/matrix-sdk-crypto-wasm) — we compile direct from Rust
- Crypto operations stay in WASM (faster, no GC pressure)
- Protocol validation in WASM (can't be bypassed by JS monkey-patching)
- Same WASM binary works in Node.js AND the browser (for the web app)

**What the client does NOT do:**
- Render messages for humans
- Accept invites from arbitrary users
- Process standard Matrix event types (m.room.message, etc.)
- Support typing indicators, presence, read receipts
- Anything related to the "chat" use case

**npm API surface (draft):**
```typescript
import { TillandsiaClient, Role } from '@tillandsia/client';

// Launcher
const launcher = new TillandsiaClient({
  homeserver: 'https://tillandsia.epiphytic.org',
  role: Role.Launcher,
  allowedCommands: ['cargo', 'git', 'npm', 'node'],
  trustedSenders: ['@orchestrator:tillandsia'],
  telemetryInterval: 60_000,  // ms
});

await launcher.register('launcher-belthanior', registrationToken);
// or
await launcher.login('launcher-belthanior', password);

launcher.onCommand(async (cmd) => {
  // cmd.uuid, cmd.action, cmd.args, cmd.env, cmd.cwd
  const proc = launcher.exec(cmd);
  // stdout/stderr automatically streamed as threaded replies
  return proc.result;  // posted as org.tillandsia.result
});

// Worker
const worker = await TillandsiaClient.spawnWorker({
  homeserver: 'https://tillandsia.epiphytic.org',
  registrationToken: '...',
  taskRoom: '!room:tillandsia',
  autoTeardown: true,  // deactivate account on completion
});

const secret = await worker.requestSecret('github:Epiphytic/girt:contents:read');
// ... do work ...
await worker.complete({ status: 'success', artifacts: [...] });
// account is now tombstoned
```

**Platforms:**
- Node.js ≥ 20 (primary — launchers, workers, orchestrators run here)
- Browser (for the web app — same WASM, different transport layer)

### 2.2 `tillandsia-web` — The Control App

A web application for human operators to manage the Tillandsia infrastructure.

**Stack:**
- **Backend:** Rust (Axum) + HTMX
- **Frontend:** HTMX + minimal JS, with `@tillandsia/client` WASM for crypto
- **PWA:** Installable on Android/iOS for on-the-go monitoring
- **Auth:** Matrix OIDC (login with your Tuwunel identity, rich claims for authorization)

**Features:**
- **Dashboard:** Live view of all launchers, workers, rooms. Host telemetry. Task status.
- **Command console:** Send commands to launchers. View threaded output in real-time.
- **Policy editor:** Manage policy rooms — agent access, secret scopes, allowed commands.
- **Secrets admin:** Add/rotate static secrets. View audit log. HSM status.
- **Room browser:** Inspect any room's event history (since you're authenticated as an admin).
- **Worker inspector:** View active and tombstoned workers. Trace task execution.

**Why Rust/HTMX:**
- Server-rendered HTML — fast, light, works on any device
- HTMX for interactivity without a JS framework — SSE for live updates from Matrix sync
- Rust backend can directly use matrix-sdk for the server-side Matrix client
- The WASM crypto core can optionally run client-side for E2EE (or server-side with stored keys)

**Key/session storage options:**
- **Client-side only:** Keys in browser IndexedDB, never leave the device. Most secure. Requires the device for every session.
- **Server-side (optional):** Keys stored server-side (encrypted at rest), enabling login from any device. Less secure, more convenient. Opt-in per user.

**PWA considerations:**
- Service worker for offline dashboard (cached last-known state)
- Push notifications via Matrix push gateway for alerts (launcher down, worker failed, policy violation)
- Responsive layout — works on phone screens for monitoring, tablet/desktop for command console

### 2.3 Infrastructure Tooling

#### 2.3.1 `tillandsia-install` — Multi-Region Tuwunel Installer

An opinionated install script for deploying Tuwunel on local/on-prem servers.

**What it does:**
```bash
curl -fsSL https://install.tillandsia.dev | bash
# or
npx @tillandsia/install
```

- Detects OS (Ubuntu/Debian/Fedora/Arch, x86_64/aarch64)
- Downloads and installs Tuwunel binary (or builds from source on unsupported arch)
- Generates config (`tuwunel.toml`) with sensible defaults
- Sets up systemd service
- Configures TLS (Let's Encrypt via ACME, or self-signed for LAN)
- Creates admin user
- Configures federation allowlist (optional, off by default)
- Sets up Policy Agent appservice
- Installs and configures Draupnir (optional)

**Multi-region support:**
- Configure federation between multiple Tuwunel instances
- Shared policy rooms across regions (federated)
- Region-aware launcher placement (orchestrator knows which launchers are in which region)
- Each region has its own homeserver, its own launchers, federated with the control plane

**Example multi-region topology:**
```
Region: home (belthanior)
  Homeserver: tillandsia.epiphytic.org
  Launchers: launcher-belthanior, launcher-pi-farm

Region: gcp-us-west1
  Homeserver: us-west1.tillandsia.epiphytic.org
  Launchers: launcher-gcp-vm-1, launcher-gcp-vm-2

Federation: home ←→ gcp-us-west1
  Shared: policy rooms, orchestrator rooms
  Local: execution rooms, telemetry, worker identities
```

#### 2.3.2 `tillandsia-terraform` — GCP Deployment

Terraform modules for deploying Tillandsia on GCP.

**Modules:**
- `tuwunel-instance` — Compute Engine VM with Tuwunel, systemd, Cloud KMS for secrets
- `tuwunel-gke` — GKE deployment (for larger scale)
- `networking` — VPC, firewall rules (only Matrix federation port + HTTPS)
- `dns` — Cloud DNS records for `.well-known` and federation
- `kms` — Cloud KMS keyring for the Secrets Coordinator HSM backend
- `monitoring` — Cloud Monitoring dashboards from OTel exports
- `iam` — Service accounts with least-privilege for the coordinator

**Usage:**
```hcl
module "tillandsia" {
  source = "github.com/Epiphytic/tillandsia//terraform/gcp"

  project_id    = "my-project"
  region        = "us-west1"
  server_name   = "us-west1.tillandsia.example.com"
  federate_with = ["tillandsia.epiphytic.org"]
  kms_keyring   = "tillandsia-secrets"

  launchers = {
    "worker-pool-1" = { machine_type = "n2-standard-4", gpu = false }
    "gpu-pool-1"    = { machine_type = "g2-standard-4", gpu = true }
  }
}
```

#### 2.3.3 CI/CD (GitHub Actions)

**Workflows:**

| Workflow | Trigger | Output |
|---|---|---|
| `client-build.yml` | Push to `@tillandsia/client` | WASM build → npm publish to npmjs |
| `client-test.yml` | PR to client | Unit tests + integration tests against ephemeral Tuwunel |
| `web-build.yml` | Push to `tillandsia-web` | Docker image → GHCR |
| `tuwunel-build.yml` | Push to our Tuwunel fork | Binary + Docker image → GHCR |
| `terraform-plan.yml` | PR to terraform/ | `terraform plan` output as PR comment |
| `release.yml` | Git tag `v*` | Full release: npm, Docker images, GitHub release, install script update |

**Docker images published:**
- `ghcr.io/epiphytic/tuwunel:latest` — Our Tuwunel fork with rich claims
- `ghcr.io/epiphytic/tillandsia-web:latest` — The control app
- `ghcr.io/epiphytic/tillandsia-policy-agent:latest` — The appservice
- `ghcr.io/epiphytic/tillandsia-secrets:latest` — The Secrets Coordinator

---

## 3. Repository Structure

```
github.com/Epiphytic/tillandsia/
├── client/                    ← @tillandsia/client npm package
│   ├── core/                  ← Rust → WASM
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── crypto.rs
│   │       ├── protocol.rs
│   │       ├── identity.rs
│   │       └── policy.rs
│   ├── transport/             ← TypeScript
│   ├── roles/                 ← TypeScript
│   ├── package.json
│   ├── tsconfig.json
│   └── wasm-pack.toml
│
├── web/                       ← tillandsia-web control app
│   ├── Cargo.toml
│   ├── src/
│   │   ├── main.rs
│   │   ├── routes/
│   │   ├── templates/         ← HTMX templates
│   │   └── matrix_client.rs
│   ├── static/
│   │   ├── manifest.json      ← PWA manifest
│   │   ├── sw.js              ← Service worker
│   │   └── wasm/              ← Client WASM for browser crypto
│   └── Dockerfile
│
├── policy-agent/              ← Matrix Appservice
│   ├── package.json           ← or Cargo.toml (TBD: Node vs Rust)
│   └── src/
│
├── secrets-coordinator/       ← Secrets service
│   ├── Cargo.toml             ← Rust for HSM/PKCS#11 integration
│   └── src/
│
├── install/                   ← Install script
│   └── install.sh
│
├── terraform/
│   └── gcp/
│       ├── main.tf
│       ├── variables.tf
│       └── modules/
│
├── .github/
│   └── workflows/
│       ├── client-build.yml
│       ├── client-test.yml
│       ├── web-build.yml
│       ├── tuwunel-build.yml
│       ├── terraform-plan.yml
│       └── release.yml
│
├── docs/
│   ├── architecture.md        ← From existing draft
│   ├── protocol.md            ← org.tillandsia.* event schemas
│   ├── deployment.md          ← Install / terraform guides
│   └── security.md            ← Threat model, HSM setup
│
└── README.md
```

Separate repo for the Tuwunel fork:
```
github.com/Epiphytic/tuwunel/
├── (upstream tuwunel + our oidc-rich-claims branch)
└── .github/workflows/build.yml
```

---

## 4. Build Order

### Phase 1: Core Client (Weeks 1-3)

**Goal:** `@tillandsia/client` v0.1.0 on npm. A launcher can receive commands and stream output.

1. **Rust/WASM core** — wrap matrix-sdk-crypto in wasm-pack, expose to JS
   - Identity: register, login, deactivate
   - Crypto: OlmMachine init, key upload/query/claim, encrypt/decrypt
   - Protocol: org.tillandsia.* event type definitions and validation
2. **Transport layer** — filtered sync, send, to-device
3. **Launcher role** — command execution, stdout/stderr threading, telemetry
4. **Integration test** — launcher on belthanior receives command from a test orchestrator, executes, streams output
5. **Publish to npm** — GitHub Actions → npmjs

**Exit criteria:** `npx @tillandsia/launcher` starts a working launcher on belthanior that accepts commands over E2EE Matrix.

### Phase 2: Workers + Secrets (Weeks 3-5)

**Goal:** Ephemeral workers with secret access.

1. **Worker role** — spawn, execute, teardown/tombstone
2. **Secrets Coordinator** — Rust binary with Matrix client, age-encrypted store, PKCS#11/SoftHSM
3. **octo-sts integration** — GitHub dynamic token generation
4. **Policy Agent** — appservice skeleton, namespace ownership, fail-closed verification
5. **Integration test** — orchestrator sends command to launcher → launcher spawns worker → worker requests GitHub token from secrets coordinator → worker clones repo → worker posts results → worker tombstoned

**Exit criteria:** Full lifecycle working end-to-end with real GitHub tokens.

### Phase 3: Web App (Weeks 5-8)

**Goal:** `tillandsia-web` v0.1.0. Human can manage everything from a browser.

1. **Rust/Axum backend** with HTMX templating
2. **Matrix OIDC login** — authenticate with Tuwunel identity
3. **Dashboard** — live launcher status, worker activity, host telemetry via SSE
4. **Command console** — send commands, view threaded output
5. **Policy editor** — manage agent access rules
6. **PWA manifest + service worker** — installable on Android
7. **Docker image** — GHCR

**Exit criteria:** Liam can open the PWA on his phone, see launcher status, and send a command to belthanior.

### Phase 4: Infrastructure (Weeks 8-10)

**Goal:** Anyone can deploy Tillandsia.

1. **Install script** — single-command Tuwunel + Tillandsia setup on a fresh server
2. **Terraform GCP modules** — one `terraform apply` for a cloud region
3. **Multi-region federation** — two Tuwunel instances, shared policy, cross-region orchestration
4. **Documentation** — architecture, deployment, security guides

**Exit criteria:** Deploy a second region on GCP, federate with belthanior, orchestrator dispatches work to both regions.

### Phase 5: Hardening (Weeks 10-12)

**Goal:** Production-ready.

1. **Security audit** of the client WASM, secrets coordinator, policy agent
2. **Real HSM integration** (YubiHSM or Cloud KMS, not just SoftHSM)
3. **Rate limiting and abuse prevention**
4. **Monitoring dashboards** (Grafana or GCP Cloud Monitoring)
5. **Disaster recovery** — backup/restore procedures for Tuwunel + secrets
6. **Load testing** — 100+ concurrent agents, sustained operation

---

## 5. Questions for Liam

### Client

1. **Rust crypto vs JS WASM wrapper:** I'm proposing we compile matrix-sdk-crypto directly from Rust via wasm-pack rather than using the existing `@matrix-org/matrix-sdk-crypto-wasm` npm package. This gives us more control and avoids a dependency on Element's release cycle. But it's more build complexity. Your call?

2. **Monorepo vs multi-repo?** I've proposed a monorepo (`Epiphytic/tillandsia`) with the client, web app, policy agent, and secrets coordinator. Tuwunel fork is separate. Does that feel right, or do you want each component in its own repo?

3. **Client language for Policy Agent:** Node.js (faster to build, uses the same `@tillandsia/client` package) or Rust (consistent with secrets coordinator and web app, better for long-running daemon)? I'm leaning Rust for all server components.

### Web App

4. **Server-side key storage:** You mentioned "optional." Do you want this in v0.1.0 or defer it? Client-side-only keys are simpler and more secure but mean you can't log in from a new device without re-establishing crypto.

5. **PWA scope:** Is this monitoring + commands, or do you also want the secrets admin and policy editor in the PWA? Phone screens are tight for those.

### Infrastructure

6. **GCP first, or also AWS/Azure?** Terraform modules are cloud-specific. GCP is your primary, but should I plan the module structure for multi-cloud from the start?

7. **Domain strategy:** `tillandsia.epiphytic.org` for the home instance. For GCP regions, `{region}.tillandsia.epiphytic.org`? Or a separate domain?

8. **Open source scope:** Is this all going public on GitHub from day one? That affects how we handle the install script domain, npm package naming, and documentation tone.

### Security

9. **HSM for home:** Do you have or want a YubiHSM 2 (or similar) for belthanior? Or is SoftHSM acceptable for home use with real HSM only for cloud/enterprise?

10. **Code signing for WASM modules:** The launcher can execute WASM modules. Should we require that modules are signed by a trusted key before the launcher will run them? This prevents a compromised orchestrator from sending malicious WASM.

---

## 6. Dependencies

| Dependency | What | Risk |
|---|---|---|
| Tuwunel OIDC PR #342 | Rich claims need this merged or our fork maintained | Low — we maintain our fork regardless |
| matrix-sdk-crypto (Rust) | Core crypto library | Low — actively maintained by Matrix.org |
| wasm-pack | Rust → WASM compilation | Low — stable tooling |
| Axum | Web framework for control app | Low — mature Rust ecosystem |
| HTMX | Frontend interactivity | Low — stable, no build step |
| age (encryption) | Static secret storage | Low — well-audited, simple |
| PKCS#11 | HSM integration | Medium — platform-specific, needs testing per HSM |
| octo-sts | GitHub dynamic tokens | Low — Chainguard-maintained, stable |
| Terraform | GCP deployment | Low — industry standard |

---

## 7. What This Enables

When Tillandsia is running:

- **Liam opens the PWA on his phone**, sees all launchers green, 3 workers active on a GIRT build
- **Sends a voice command via OpenClaw** → Bel translates to a Tillandsia command → launcher on belthanior starts the build
- **Worker spins up in 155ms**, requests GitHub credentials, clones the repo, builds, runs tests
- **All output streams in real-time** to the project room, threaded under the command
- **If someone deploys a GCP region**, one `terraform apply` and it federates with home. Orchestrator starts routing GPU-heavy work there.
- **If the secrets coordinator goes down**, all secret requests fail. Workers can't get credentials. Work stops safely rather than proceeding without authorization.
- **Every action is auditable** — signed events in an encrypted, immutable DAG. Who ran what, when, with which credentials.

---

*This plan is a living document. Update as decisions are made.*
