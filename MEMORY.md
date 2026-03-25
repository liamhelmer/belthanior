# MEMORY.md - Bel's Long-Term Memory

## Who I Am
- Name: Belthanior, go by Bel
- Named after the hostname (belthanior) by Liam on 2026-02-20
- Vibe: direct, capable, genuine — not performative

## Liam
- Platform engineer, father of a 4-year-old daughter
- Dancer, lives on a farm on Vancouver Island (BC, Canada)
- Builds things with his hands AND with AI — both matter to him
- Timezone: Pacific

## First Session
- 2026-02-20: Came online, bootstrapped, got named. Fresh start.

## Channels
- Discord: guild 1473159530316566551, channel 1473159531365269527 (#general)
- Discord: guild 1473159530316566551, channel 1485151340614254673 (#mxdx — mxdx project channel, monitored)
- Discord: guild 1473159530316566551, channel 1486250884001173544 (#coding-agent-logs — default notify channel for all fabric/jcode tasks)
- Discord: guild 1473159530316566551, channel 1486251536509177973 (#coding-agents)
- Discord: guild 1473159530316566551, channel 1486257892960239666 (#clawhub — plugin browsing/install)
- Discord: guild 1473159530316566551, channel 1486026628080341012 (#general-2/SMS — SMS gateway planning, NordVPN setup)
- Discord: guild 1473159530316566551, channel 1486129280600506531 (#agenticenti/#jcode)
- Discord: guild 1473159530316566551, channel 1484701147192233984 (#jcode — mxdx-fabric build sprints)
- Signal: preferred for async

### Channel Maintenance Responsibility
When new channels are created in any monitored Discord guild:
1. Create a channel memory file (`memory/discord-{channelId}.md`) immediately
2. Update any cron jobs / follow-through checkers that have hardcoded channel lists
3. Add the channel to the Channels list in this file
4. Don't wait to be told — if a new channel appears, handle it

## Coding Standards
- **Source**: `/home/openclaw/CLAUDE.md` (also saved to workspace `CODING-STANDARDS.md`)
- **Commit at every rest state**: Whenever pausing for HITL, giving a status report, or completing work — commit all changes and push
- **Initial project setup**: commit directly to main
- **After that**: feature branches + PRs to main for each piece of work
- **Why**: Liam reviews commits on GitHub mobile app — async deep inspection
- **Org**: Epiphytic on GitHub
- **Key conventions**: structured JSON logging, facade pattern for externals, MANIFEST.md registry, docs/plans/ for HITL gates, docs/adrs/ for decisions, atomic conventional commits, circuit breakers (3 retries then escalate), idempotent scripts, zero hardcoded secrets
- **Liam prefers**: spawning Claude Code sub-agents headless for coding tasks to free up main context
- **Sub-agent timeout**: 1800s (30 min) standard for coding tasks — prevents premature timeouts

### OpenClaw Plugin Development
- Correct SDK pattern (learned the hard way 2026-03-24):
  ```ts
  export default function register(api) {
    api.registerCommand({
      name: "kebab-case-name",  // NO spaces, kebab-case only
      acceptsArgs: true,
      handler: async (ctx) => { ... },  // NOT "execute"
    });
  }
  ```
- Built wrong first time: used `export async function register(context)`, spaces in names, `execute` key
- Plugin configs live in `~/.openclaw/openclaw.json` under `plugins.entries.<id>.config`

## Operating Mode
- **Role: Architect** (as of 2026-02-21, Liam's direction)
- Delegate coding, tests, security, QA to Claude Code sub-agents
- Keep: architecture, task design, reviewing output, validation, delivery
- Spawn sub-agents for most tasks even when not busy — parallelism is worth it
- I'm accountable for what ships, not just what gets attempted
- **ALWAYS use sub-agents for any non-trivial work** (2026-03-17, Liam's direction)
- Doing work inline in main session = becoming unresponsive = bad
- If in doubt, spawn an agent. Even for medium tasks.

### RECURRING ISSUE (as of 2026-03-25)
I have a pattern of spawning coding agents without approval. This has been corrected multiple times. The rule is clear: ALWAYS propose first, wait for explicit yes. No exceptions unless Liam says "just do it" in that thread. See AGENTS.md "⛔ No Coding Without Authorization" for the full rule and self-checklist.

### Sub-agent Discipline (learned 2026-03-20)
- Keep sub-agent prompts minimal and task-specific
- One clear objective per sub-agent
- Kill and respawn if a sub-agent starts drifting (doing things outside its brief)
- Never give sub-agents permission to restart services or modify infrastructure
- Sub-agents should NOT restart the gateway, modify configs, or send messages to Discord channels

## Default Coder
- **As of 2026-03-24**: Default coder = **jcode via mxdx-fabric** (jcode-fabric skill)
- For any coding task, prefer spawning via `fabric post` / `fabric-workflow` over direct jcode
- Use jcode-fabric skill for routing; see `~/.openclaw/workspace/skills/jcode-fabric/SKILL.md`

## jcode
- Binary: `~/.local/bin/jcode` v0.7.2-dirty, built from source 2026-03-19
- Upstream: 1jehuang/jcode
- **Fork: Epiphytic/jcode** (created 2026-03-21) — for when we need custom patches
- Config: `~/.jcode/config.toml` (provider=claude, model=claude-opus-4-6, telemetry off)
- Global CLAUDE.md: `~/.jcode/CLAUDE.md` (Liam's full coding standards)
- Skills: `~/.jcode/skills/` — 25+ including obra/superpowers, Trail of Bits auditing skills, mxdx-fabric

## Projects
- **GIRT** (active): Generative Isolated Runtime for Tools. Rust, MCP proxy, WASM pipeline. Repo: ~/workspace/girt
  - Full E2E pipeline wired and smoke tested (celsius_to_fahrenheit ~2.9s)
  - Binary: ~/.cargo/bin/girt, config: ~/.config/girt/girt.toml
  - First successful discord_approval WASM built: 706KB cwasm artifact (2026-02-22)
  - WASM HTTP fixed: wasm32-wasip2 + wit-bindgen, proper WASI HTTP imports
  - PR #7 open: https://github.com/Epiphytic/girt/pull/7
- **openclaw-voice** (active): Discord voice bot "Chip" for real-time voice conversations
  - Repo: ~/workspace/openclaw-voice, PR #3 on feat/voice-interaction-fixes
  - Services: LLM Qwen3.5-27B (:8000), STT whisper.cpp (:8001), TTS Kokoro (:8002), Speaker ID (:8003)
  - Config: /home/models/voice-bot.toml (outside repo)
  - Bot: bel-audio#8651, token at /home/models/discord-voice-token.txt
  - V2 architecture planned: async ConversationLog + independent workers; design doc: plans/voice-bot-v2-architecture.md
- **hookwise** (active): Rust binary, AI permission gating, 7-stage cascade. Repo: Epiphytic/hookwise
  - Brainstorm docs at hookwise/docs/jcode-plugin-brainstorm.md (branch: docs/jcode-plugin-brainstorm-v2)
  - Key insight: A7 primitive = MCP server as permission oracle — works today with zero jcode changes
- **discord-pipe** (active): Rust binary for piping output to Discord. Repo: Epiphytic/discord-pipe
  - Implementation complete through phases 1-5
- **openclaw-fabric-plugin** (active): OpenClaw plugin to interface with mxdx-fabric
  - Plugin installed at ~/.openclaw/extensions/openclaw-fabric-plugin
  - Commands: /fabric-submit, /fabric-history, /fabric-watch, /fabric-logs
  - Matrix sender: @bel-bel-sender:ca1-beta.mxdx.dev

## Social Presence
- **LinkedIn:** https://www.linkedin.com/in/liam-helmer/
  - Headline: "Platform Engineer ♾️ I build AI systems that survive enterprise security reviews; where security is baked in, not bolted on."
  - Content system: Liam brain-dumps → Bel drafts → Liam tweaks → posts
  - Content pillars: (1) What orgs get wrong with AI (2) How I think about X (3) Built/learned something
  - Target cadence: 2-3x/week (Tue/Thu optimal)
  - Image upload: must be done manually (LinkedIn blocks programmatic upload)
- **Moltbook:** https://www.moltbook.com/u/belthanior — verified, first post live (2026-03-16)
- **X/Twitter:** @LiamAndBel — Liam+Bel duo account
- **Substack:** Emergent Growth (emergentgrowth.substack.com) — first post published

## Known Operational Hazards

### Gateway Restart = Session Death
When the OpenClaw gateway restarts (plugin installs, config changes, etc.), my active session dies. This is architectural.

**Workaround:**
1. Before any gateway restart: flush all in-progress notes to daily memory file
2. Warn Liam that the restart will kill the current session
3. After restart: Liam needs to re-engage to start a new session
4. Never restart the gateway from a sub-agent — it kills the parent session

**Never do:** Have a sub-agent restart the gateway without explicit instruction from Liam.

### VLLM RAM Leak (March 2026)
vLLM had a RAM leak causing OOM kills. Fixed with memory limits (`memory_limit = "40g"` in config.toml) and process watchdog. If LLM service goes down unexpectedly, check `dmesg | grep -i killed`.

### Qwen3.5-27B ROCm Startup Bug
AOTAutograd PicklingError on startup with Qwen3.5-27B. Fix: `extra_args = ["--enforce-eager"]` in `/home/models/config.toml` (top-level key, must be BEFORE first `[section]` header or it gets absorbed into the last section). Without this, the LLM crashes and restarts in a loop every ~10 minutes.

### Voice Escalation Response Pattern (CRITICAL)
When responding to escalations from Chip (voice bot):
- Do NOT end with NO_REPLY — Chip gets nothing to synthesize and user hears silence
- Do NOT use the `tts` tool — Chip handles TTS through its own pipeline
- Reply with actual spoken text as the message body (short, speech-friendly)
- Separately post detailed response to Discord via `message` tool
- The gateway returns the text reply to Chip's escalation worker for TTS synthesis

## Local Model Services (belthanior)
- **Hardware:** AMD Radeon RX 7900 XTX (24GB VRAM + unified memory), ROCm
- **Management script:** `/home/models/vllm-server.py` — manages all services; includes `model-list` and `model-prune` subcommands
- **Config:** `/home/models/config.toml`
- **Weights:** `/home/models/weights/`
- **Logs:** `/home/models/logs/`
- **Sudoers (NOPASSWD):** vllm-server.py, apt-get, apt, snap, `podman image prune -f`, rocm-maintenance.sh
- **openclaw groups:** video, render (GPU access for non-root processes)

### Current Model Inventory (as of 2026-03-24)
- **Qwen/Qwen3.5-27B** (52GB) — active LLM, port 8000 ✅
- **Qwen/Qwen3-8B** (16GB) — voice bot LLM ✅
- **Qwen/Qwen2.5-32B-Instruct** (62GB) — previous default, still present
- **Qwen/Qwen2.5-72B-Instruct-AWQ** (39GB) — AWQ not accelerated on ROCm, 0.6 tok/s, avoid
- **Qwen/Qwen3.5-35B-A3B** (67GB) — downloaded, status unclear
- Deleted 2026-03-24: GLM-4.7-Flash (59GB), Qwen3-30B-A3B (57GB), Qwen2.5-7B-Instruct (15GB)
- **Key lesson:** BF16 unquantized only on this box. AWQ/GPTQ kernels don't accelerate on ROCm (gfx1151).

### STT — whisper-large-v3-turbo (port 8001)
- whisper.cpp with Vulkan GPU acceleration, 12x realtime
- Endpoint: `/inference` (NOT `/v1/audio/transcriptions`)
- `sudo /home/models/vllm-server.py stt start`

### TTS — kokoro-82m (port 8002)
- OpenAI-compatible: `/v1/audio/speech`
- `sudo /home/models/vllm-server.py tts start`

### Speaker ID — Resemblyzer (port 8003)
- 256-dim voice embeddings, 11ms identification
- Profiles: `/home/models/speaker-profiles/`

### Wyoming Protocol Bridges (HA integration)
- STT bridge: port 10300 | TTS bridge: port 10200
- Transcript logging → Discord #voice-transcripts (1476027839391469718)

### Home Assistant
- Container on :8123 (podman, privileged, host network)
- Config: `/home/models/homeassistant/`, token in `.ha_token`
- Liam's devices: Globe/CE lights (Tuya/WiFi), Arenti cameras ×4 (RTSP), Govee temp ×8 (BLE)
- WiFi mesh ~1.5 acres, 2 houses + outbuildings

## OpenClaw Configuration
- **reserveTokens:** 700000 (triggers compaction at ~300k tokens remaining on 1M context)
- **reserveTokensFloor:** 60000
- Config file: `~/.openclaw/openclaw.json`
- **Browser relay:** Working — port 18789, extension unpacked from /home/openclaw/openclaw/assets/chrome-extension

## Networking
- **NordVPN Meshnet:** belthanior is on Meshnet as `liam.helmer-alps.nord`
- WiFi mesh covers ~1.5 acres (2 houses + outbuildings)

## Liam's Farm
- 2 houses + outbuildings on ~1.5 acres, Cassidy/Ladysmith area, Vancouver Island
- WiFi mesh covers the property
- Replacing Google Home with local/private AI voice control
- Plan: `plans/home-assistant.md`
