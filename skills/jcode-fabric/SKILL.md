---
name: jcode-fabric
description: "Run jcode coding tasks via the mxdx-fabric layer (Matrix-based task queue). Use instead of the jcode skill when: tasks need to survive session restarts, fabric routing is explicitly requested, or multi-machine worker dispatch is needed. Routes through the mxdx-fabric coordinator on ca1-beta.mxdx.dev. NOT for: quick one-off tasks where direct jcode is simpler, or when the fabric services are known to be down."
---

# jcode-fabric Skill

Routes jcode tasks through the mxdx-fabric coordinator → worker pipeline instead of running jcode directly.

## Infrastructure

- **Coordinator & worker:** Running as systemd user services (`mxdx-fabric-coordinator.service`, `mxdx-fabric-worker.service`) — check with `systemctl --user status mxdx-fabric-coordinator mxdx-fabric-worker`
- **Config:** `~/.config/mxdx-fabric/config.toml` (homeserver, coordinator room, sender token pre-configured)
- **Homeserver:** `https://ca1-beta.mxdx.dev`
- **CLI binary:** `~/.local/bin/fabric`

## Discover Worker Capabilities

Run `fabric capabilities` to discover current accepted args for this host's worker. Filter by worker ID with `fabric capabilities @bel-worker:ca1-beta.mxdx.dev`.

Example output:

```
Worker: @bel-worker:ca1-beta.mxdx.dev (host: belthanior)
  Tool: jcode v0.7.2 [healthy]
    cwd              string              Absolute working directory path
    prompt           string   (required)  Task prompt
```

Each tool entry shows: name, version, health status, and an `inputSchema` listing accepted fields (type, required/optional, description). Use this output to determine what payload fields the worker currently accepts before posting a task.

## Post a Task

```bash
fabric post \
  --capabilities "rust,linux,bash" \
  --prompt "your task prompt here" \
  --timeout 1800
```

The `post` command blocks until the result comes back (or timeout). Output is raw NDJSON (jcode streaming format) — decode at the caller layer, not in the skill.

To pass fields like `cwd` or `model`, embed them in the prompt as context or wait for payload-passthrough to be added to the CLI.

## Typical Invocation (via subagent)

Always spawn a subagent — fabric post blocks for up to 30 min:

```
sessions_spawn(task="Run: fabric post --capabilities 'rust,linux,bash' --prompt '[task]' --timeout 1800. Report full output back.")
```

Pipe long output to Discord webhook using the same `discord-pipe` pattern as the jcode skill if needed.

## Check Service Health Before Posting

```bash
systemctl --user is-active mxdx-fabric-coordinator mxdx-fabric-worker
```

If either is inactive, restart with:

```bash
systemctl --user restart mxdx-fabric-coordinator mxdx-fabric-worker
```

## Known Limitations

- Raw NDJSON output: caller is responsible for decoding
- OAuth token for jcode expires ~5h after last browser auth — if worker silently fails, re-auth via `jcode auth login` on belthanior
