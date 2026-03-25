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
  Tool: jcode vunknown [healthy]
    cwd              string               Absolute working directory path (no .. components)
    model            string               Model override (e.g. claude-opus-4-6)
    prompt           string   (required)  Task prompt
    quiet            boolean              Suppress status output
    resume_session   string               Session UUID to resume a prior jcode session
```

Each tool entry shows: name, version, health status, and accepted fields (type, required/optional, description). Always run this before posting to confirm which fields the worker currently accepts.

## Post a Task

```bash
fabric post \
  --capabilities "rust,linux,bash" \
  --prompt "your task prompt here" \
  --timeout 1800
```

The `post` command blocks until the result comes back (or timeout). Output is raw NDJSON (jcode streaming format) — decode at the caller layer, not in the skill.

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

## fabric-run (Single Task with Discord Notifications)

Wraps `fabric post` with Discord start/completion notifications and streaming output to a webhook channel.

```bash
fabric-run --label "Task N - description" [--notify-channel ID] [--webhook-channel ID] -- "task prompt"
```

Output is decoded via `jcode-decode` and streamed to Discord via `discord-pipe`.

## fabric-workflow (Multi-Phase Git Workflow Orchestrator)

Orchestrates multi-phase coding work across feature branches, worktrees, and PRs. Sits above `fabric-run`.

### What it Does

Given a feature name and a list of phases (each with tasks):

1. Creates `feat/<feature-name>` branch from base (default: `main`)
2. Per phase:
   - Creates phase branch `feat/<feature-name>/phase-<N>-<slug>` from feature branch
   - Creates a git worktree at `/tmp/worktrees/<feature-name>/phase-<N>`
   - Runs each task sequentially via `fabric-run` with the worktree as working directory
   - Pushes phase branch, opens PR to feature branch
   - Attempts automerge (`gh pr merge --auto --squash`), waits for merge (10min timeout)
   - Cleans up worktree after merge
3. After all phases merge, opens a final PR from feature branch to base branch
4. Posts PR link to Discord and waits for approval

### Usage

**Via TOML spec file** (recommended for multi-task phases):

```bash
fabric-workflow --spec /path/to/workflow.toml [--dry-run]
```

**Via CLI arguments:**

```bash
fabric-workflow \
  --repo /path/to/repo \
  --feature "my-feature-name" \
  --notify-channel 1486250884001173544 \
  -- phase1_name "task1 prompt" "task2 prompt" \
  ::: phase2_name "task1 prompt"
```

### Spec File Format (TOML)

```toml
repo = "/path/to/repo"
feature = "my-feature-name"
notify_channel = "1486250884001173544"
base_branch = "main"                    # optional, default: main

[[phase]]
name = "setup"
tasks = [
  "Initialize the module structure and add boilerplate",
  "Add configuration parsing with serde",
]

[[phase]]
name = "implementation"
tasks = [
  "Implement the core business logic",
]

[[phase]]
name = "tests"
tasks = [
  "Add unit tests for all public functions",
  "Add integration tests",
]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--spec FILE` | TOML workflow spec file | - |
| `--repo PATH` | Repository path | - |
| `--feature NAME` | Feature name (branch naming) | - |
| `--notify-channel ID` | Discord channel for notifications | `1486250884001173544` (#coding-agent-logs) |
| `--base-branch NAME` | Base branch to target | `main` |
| `--dry-run` | Print actions without executing | `false` |

### Workflow Behavior

- **Worktrees:** Script creates them; jcode works in them via `cwd` in prompt. jcode never touches git.
- **All git ops** (branch, worktree, push, PR) are done by the script using `git` and `gh` CLI.
- **Commit links:** `https://github.com/<owner>/<repo>/commit/<hash>` - extracted from worktree git log.
- **PR bodies:** Include task lists with commit links and fabric task references.
- **Graceful degradation:** If automerge is not enabled on repo, posts PR link and continues (does not block).
- **Error handling:** If a task fails (non-zero exit), stops the phase, posts failure to Discord, exits.

### Example: Running a Multi-Phase Feature

```bash
# Create a workflow spec
cat > /tmp/my-feature.toml <<'EOF'
repo = "/home/openclaw/.openclaw/workspace/mxdx"
feature = "add-retry-logic"
notify_channel = "1486250884001173544"

[[phase]]
name = "types"
tasks = [
  "Add RetryPolicy and RetryConfig types to mxdx-types with serde support",
]

[[phase]]
name = "implementation"
tasks = [
  "Implement retry logic in mxdx-fabric worker using the new RetryPolicy types",
  "Add exponential backoff with jitter to the retry implementation",
]

[[phase]]
name = "tests"
tasks = [
  "Add comprehensive tests for retry logic including edge cases",
]
EOF

# Dry run first
fabric-workflow --spec /tmp/my-feature.toml --dry-run

# Execute
fabric-workflow --spec /tmp/my-feature.toml
```

## Known Limitations

- Raw NDJSON output: caller is responsible for decoding
- OAuth token for jcode expires ~5h after last browser auth - if worker silently fails, re-auth via `jcode auth login` on belthanior
- `fabric-workflow` automerge requires the repo to have automerge enabled in GitHub settings
- `fabric post` does not currently support passing `cwd` as a separate field; `fabric-workflow` embeds the working directory in the prompt text
