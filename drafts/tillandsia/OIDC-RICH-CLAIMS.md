# OIDC Rich Claims Extension — Scoping Document

**Date:** 2025-02-27
**Branch:** `oidc-server` on `lytedev/tuwunel`
**Author:** Agent Alpha (with Liam's direction)

## 1. Overview

The Tuwunel OIDC server branch (MSC2965/2964/2966/2967) implements a basic OIDC authorization server built into the homeserver. Currently, the ID token and userinfo endpoint return minimal claims:

**Current ID Token claims (`IdTokenClaims`):**
- `iss` — Issuer URL
- `sub` — Matrix User ID (e.g., `@user:tillandsia`)
- `aud` — Client ID
- `exp`, `iat` — Timestamps
- `nonce` — Optional replay protection
- `at_hash` — Access token hash

**Current userinfo response:**
- `sub` — Matrix User ID
- `name` — Display name
- `picture` — Avatar MXC URI

## 2. Proposed Rich Claims

### 2.1 Device ID (`device_id`)

**Claim name:** `device_id`
**Location:** ID token and userinfo
**Value:** The device ID associated with the OIDC session (e.g., `"ABCDEF123"`)
**Rationale:** Allows relying parties to identify which device authorized the session, enabling per-device authorization decisions.

### 2.2 Room Memberships (`urn:matrix:rooms`)

**Claim name:** `urn:matrix:rooms` (namespaced to avoid collision)
**Location:** Userinfo only (can be large)
**Value:** Array of objects:
```json
{
  "urn:matrix:rooms": [
    {
      "room_id": "!abc:tillandsia",
      "membership": "join",
      "room_name": "General",
      "room_alias": "#general:tillandsia"
    }
  ]
}
```
**Rationale:** Enables authorization decisions based on room membership (e.g., "user must be in #admins room to access admin panel").

### 2.3 Power Levels (`urn:matrix:power_levels`)

**Claim name:** `urn:matrix:power_levels`
**Location:** Userinfo only
**Value:** Map of room_id → power level:
```json
{
  "urn:matrix:power_levels": {
    "!abc:tillandsia": 100,
    "!def:tillandsia": 50
  }
}
```
**Rationale:** Enables fine-grained authorization. A relying party can check "user has power level >= 50 in the project room."

### 2.4 Server Admin Status (`urn:matrix:admin`)

**Claim name:** `urn:matrix:admin`
**Location:** ID token and userinfo
**Value:** Boolean
```json
{
  "urn:matrix:admin": true
}
```
**Rationale:** Simple boolean for server administration access control. Lightweight enough for the ID token.

### 2.5 Policy Scopes (`urn:matrix:policy_scopes`)

**Claim name:** `urn:matrix:policy_scopes`
**Location:** Userinfo only
**Value:** Array of policy evaluations from policy rooms:
```json
{
  "urn:matrix:policy_scopes": {
    "banned": false,
    "rules": [
      {
        "type": "m.policy.rule.user",
        "entity": "@user:tillandsia",
        "reason": null,
        "recommendation": null
      }
    ]
  }
}
```
**Rationale:** Enables relying parties to enforce ban lists and moderation decisions. This is powerful for federated authorization — a Draupnir policy list could influence access control in external services.

## 3. Files That Need to Change

### 3.1 `src/service/oauth/oidc_server.rs` — IdTokenClaims struct

**Current state (lines 99-110):**
```rust
pub struct IdTokenClaims {
    pub iss: String,
    pub sub: String,
    pub aud: String,
    pub exp: u64,
    pub iat: u64,
    pub nonce: Option<String>,
    pub at_hash: Option<String>,
}
```

**Changes needed:**
- Add `device_id: Option<String>` field
- Add `urn:matrix:admin` field (via serde rename): `#[serde(rename = "urn:matrix:admin", skip_serializing_if = "Option::is_none")] pub is_admin: Option<bool>`
- ~10 lines added

### 3.2 `src/api/client/oidc.rs` — Token endpoint (ID token construction)

**Current state (lines 332-351):** `token_authorization_code()` constructs `IdTokenClaims`

**Changes needed:**
- After creating the device, query admin status via `services.admin.user_is_admin(&user_id).await`
- Pass `device_id` from the created device into claims
- ~8 lines added

### 3.3 `src/api/client/oidc.rs` — Userinfo endpoint

**Current state (lines 450-473):** `userinfo_route()` returns `sub`, `name`, `picture`

**Changes needed:**
- Query `services.rooms.state_cache.rooms_joined(&user_id)` for room memberships
- For each joined room, query `services.rooms.state_accessor.get_power_levels(&room_id)` and extract user's power level
- Query `services.rooms.state_accessor.get_name(&room_id)` for room names
- Query `services.rooms.state_accessor.get_canonical_alias(&room_id)` for room aliases
- Query `services.admin.user_is_admin(&user_id)` for admin status
- Get `device_id` from the token lookup (already available as `_device_id` — just un-ignore it)
- Query policy rooms for `m.policy.rule.user` events matching this user
- Build and return the enriched JSON response
- ~80-120 lines added

### 3.4 `src/api/client/oidc.rs` — OIDC metadata

**Current state (line 86):** `claims_supported` lists only basic claims

**Changes needed:**
- Add the new claim names to `claims_supported`
- Add `scopes_supported` entries if we gate claims behind scopes
- ~5 lines changed

### 3.5 (Optional) New file: `src/service/oauth/rich_claims.rs`

**Rationale:** If the claim-building logic becomes complex (especially policy evaluation), extract it into a dedicated module.

**Estimated size:** ~150-200 lines for a helper that:
- Gathers room memberships and power levels
- Evaluates policy rules
- Returns a structured claims object

## 4. Estimated Lines of Code

| Component | Lines Added/Changed |
|-----------|-------------------|
| `IdTokenClaims` struct expansion | ~10 |
| Token endpoint (claims construction) | ~8 |
| Userinfo endpoint (rich response) | ~80-120 |
| OIDC metadata update | ~5 |
| `rich_claims.rs` helper module (optional) | ~150-200 |
| **Total** | **~250-340 lines** |

## 5. Architectural Concerns

### 5.1 Token Size: ID Token vs Userinfo

**ID Token** is a signed JWT included in every token response. It should be small:
- ✅ Include: `device_id`, `urn:matrix:admin` (boolean) — small, fixed-size
- ❌ Exclude: room memberships, power levels, policy scopes — variable size, potentially large

**Userinfo endpoint** is fetched on-demand and can return larger payloads:
- ✅ Include: everything — room memberships, power levels, policy scopes
- Relying parties fetch this only when they need the full picture

**Recommendation:** Put `device_id` and `is_admin` in the ID token. Put everything else in userinfo only. This keeps JWTs under 1KB while allowing rich authorization queries.

### 5.2 Performance: Room Membership Queries

A user could be in hundreds of rooms. For each room we need:
1. Room name (~1 DB read)
2. Canonical alias (~1 DB read)
3. Power levels (~1 DB read + lookup)

**Mitigation strategies:**
- Cap room list at 100 rooms (configurable)
- Add optional `scope` parameter to filter rooms (e.g., only rooms matching a pattern)
- Cache results for the token lifetime
- Consider returning room IDs only by default, with names/aliases opt-in via scope

### 5.3 Policy Room Discovery

There's no built-in "find all policy rooms" function. Policy rooms are regular rooms with `m.policy.rule.*` state events. We need to:
1. Identify rooms the user is in that contain policy events (expensive scan)
2. OR maintain a config-driven list of policy room IDs
3. OR use a Draupnir-style convention (room tagged with specific type)

**Recommendation:** Use a config option `oidc_policy_rooms = ["!room:server"]` to explicitly list rooms to check for policy rules. This avoids expensive discovery scans.

### 5.4 Scope-Gated Claims

Claims should be gated behind OIDC scopes for privacy:
- `urn:matrix:org.matrix.rooms` → room memberships
- `urn:matrix:org.matrix.power_levels` → power levels
- `urn:matrix:org.matrix.admin` → admin status
- `urn:matrix:org.matrix.policy` → policy scopes

Only include claims when the client requested (and was granted) the corresponding scope.

### 5.5 Staleness

Room memberships and power levels change over time. The ID token is issued once and cached. Options:
- **Short token expiry** (5-15 min) forces frequent re-fetching
- **Userinfo endpoint** always returns live data (recommended for authorization decisions)
- **ID token** should contain only stable claims (admin status changes rarely)

## 6. Upstreamability Assessment

### Likely Upstreamable
- `device_id` in claims — standard OIDC practice, useful for all deployments
- `urn:matrix:admin` — simple boolean, server-specific but universally useful
- Scope-gated claims architecture — clean extension point

### Tuwunel-Specific Extension (Needs Discussion)
- Room memberships in userinfo — novel, no Matrix spec coverage
- Power levels in userinfo — novel, exposes internal authorization model
- Policy scopes — very Tuwunel/Draupnir-specific, no precedent

### Recommendation
Structure the implementation as a Tuwunel extension under the `_tuwunel` namespace:
- Use `urn:matrix:*` claim names (following Matrix URN conventions)
- Gate behind Tuwunel-specific scopes
- Document as experimental
- Propose to Matrix spec as MSC if it proves useful

This makes it upstreamable later while clearly marking it as experimental today.

## 7. Implementation Order

1. **Phase 1 (Quick wins):** `device_id` and `is_admin` in ID token + userinfo (~20 lines)
2. **Phase 2 (Core value):** Room memberships and power levels in userinfo (~100 lines)
3. **Phase 3 (Advanced):** Policy scope evaluation in userinfo (~120 lines)
4. **Phase 4 (Polish):** Scope-gated claims, configurable caps, caching (~100 lines)

## 8. Testing Strategy

- Unit test claim construction with mock services
- Integration test: register client → authorize → exchange code → verify ID token claims
- Integration test: access token → GET /userinfo → verify rich claims
- Benchmark: measure userinfo response time with 0, 10, 50, 200 rooms
- Verify existing Matrix client compatibility (Element, etc.) isn't broken by extra claims
