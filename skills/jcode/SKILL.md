---
name: jcode
description: "Run jcode (Rust coding agent using Claude Max OAuth) for coding tasks. Use when: (1) building/modifying code, (2) reviewing PRs or files, (3) iterative coding that needs file exploration. Supports Claude Max subscription via OAuth — no API key needed. For long-running tasks, submit via /fabric-submit and watch results on Discord. ALWAYS launch via sessions_spawn subagent — never run inline."
---

## ⚠️ Always use a subagent

jcode tasks take minutes. Always spawn a subagent so the main session stays responsive:

```
sessions_spawn(task="Run jcode: [task description] in [path]. Submit via /fabric-submit.")
```

Never run jcode inline in the main session.

# jcode Skill

jcode is a Rust-based coding agent that uses your Claude Max OAuth subscription.

## Submitting Tasks via Fabric (preferred)

Use the `/fabric-submit` command to submit jcode tasks through the fabric coordinator. Results are automatically routed back to the specified channel.

### 1. Submit the task

```
/fabric-submit --capability jcode --cwd /path/to/project --timeout 1800 --channel discord Your task prompt here
```

Flags:
- `--capability jcode` — use the jcode worker (default)
- `--cwd /path` — working directory for the task
- `--timeout SECS` — max runtime in seconds (default: 1800)
- `--channel discord` — where to send results (default: discord)

### 2. Watch for results (optional — auto-registered by fabric-submit)

If you need to manually register a watcher for an existing task:

```
/fabric-watch <task-uuid> discord
```

### 3. Inspect results

```
/fabric-history                    # recent task history
/fabric-history --status done      # completed tasks only
/fabric-history --since 1d         # last 24 hours
/fabric-logs <task-uuid>           # summary of a task's output
/fabric-logs <task-uuid> --full    # full output (multi-message)
/fabric-logs --in-progress         # list currently running tasks
```

## Quick one-off (no fabric)

```bash
JCODE_NO_TELEMETRY=1 jcode --provider claude -C /path/to/project run "your task" 2>&1
```

## Key flags

- `--provider claude` — use Claude Max OAuth
- `-C /path` — working directory
- `run "prompt"` — one-shot mode
- `--trace` — verbose tool input/output logging
- `--model claude-opus-4-6` — override model

## Auth

Check: `jcode auth status`
Test: `jcode auth-test --provider claude`
Tokens auto-refresh from `~/.claude/.credentials.json` (expire ~5h)

## Config

- Binary: `~/.cargo/bin/jcode` (57MB, v0.7.2)
- Global config: `~/.jcode/config.toml`
- Skills: `~/.jcode/skills/` (obra/superpowers + Trail of Bits + custom)
- Global standards: `~/.AGENTS.md`, `~/.CLAUDE.md`
- MCP: `~/.jcode/mcp.json` (context7 — loads in serve/TUI mode only)

## Discord Channel

- `#jcode-mxdx` channel ID: `1484445467944288278`
- Guild ID: `1473159530316566551`
- Bot token: belthanior OpenClaw bot (has Manage Webhooks permission on this channel)

## Telemetry

Always set `JCODE_NO_TELEMETRY=1` — or it's in `~/.jcode/config.toml` already.
