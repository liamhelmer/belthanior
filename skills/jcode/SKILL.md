---
name: jcode
description: "Run jcode (Rust coding agent using Claude Max OAuth) for coding tasks. Use when: (1) building/modifying code, (2) reviewing PRs or files, (3) iterative coding that needs file exploration. Supports Claude Max subscription via OAuth — no API key needed. For long-running tasks, auto-create a Discord webhook and pipe output to #jcode-mxdx channel. ALWAYS launch via sessions_spawn subagent — never run inline."
---

## ⚠️ Always use a subagent

jcode tasks take minutes. Always spawn a subagent so the main session stays responsive:

```
sessions_spawn(task="Run jcode: [task description] in [path]. Post output to Discord webhook [url].")
```

Never run jcode inline in the main session.

# jcode Skill

jcode is a Rust-based coding agent that uses your Claude Max OAuth subscription.

## Webhook-Per-Session Pattern (preferred for long tasks)

For any task longer than ~30s, create a session webhook, pipe output to Discord, delete when done.

### 1. Create webhook

```bash
OC_TOKEN="${OC_BOT_TOKEN}"
JCODE_CHANNEL="1484445467944288278"
SESSION_NAME="jcode-$(date +%Y%m%d-%H%M)-[project]"  # e.g. jcode-20260320-1630-girt

WEBHOOK_URL=$(curl -s -X POST "https://discord.com/api/v10/channels/$JCODE_CHANNEL/webhooks" \
  -H "Authorization: Bot $OC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$SESSION_NAME\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
```

### 2. Run jcode, piping output to Discord

```bash
JCODE_NO_TELEMETRY=1 jcode --provider claude -C /path/to/project run "your task" 2>&1 | \
  discord-pipe --webhook "$WEBHOOK_URL" --tag "$SESSION_NAME" --window-ms 3000 --max-lines 40
```

### 3. Delete webhook when done

```bash
WEBHOOK_ID=$(echo "$WEBHOOK_URL" | grep -oP '(?<=webhooks/)\d+')
curl -s -X DELETE "https://discord.com/api/v10/webhooks/$WEBHOOK_ID" \
  -H "Authorization: Bot $OC_TOKEN"
```

## Quick one-off (no webhook)

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
