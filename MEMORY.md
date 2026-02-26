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
- Discord: guild 1473159530316566551, channel 1473159531365269527 (dedicated GIRT workspace server)
- Signal: preferred for async

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

## Operating Mode
- **Role: Architect** (as of 2026-02-21, Liam's direction)
- Delegate coding, tests, security, QA to Claude Code sub-agents
- Keep: architecture, task design, reviewing output, validation, delivery
- Spawn sub-agents for most tasks even when not busy — parallelism is worth it
- I'm accountable for what ships, not just what gets attempted

## Projects
- **GIRT** (active): Generative Isolated Runtime for Tools. Rust, MCP proxy, WASM pipeline. Repo: ~/workspace/girt
  - **2026-02-20 session: massive build sprint**
  - Replaced Wassette subprocess with embedded `girt-runtime` crate (ADR-010) — ported from Wassette MIT
  - AnthropicLlmClient done — reads creds from OpenClaw auth-profiles.json automatically
  - Full E2E pipeline wired: request_capability → Claude (Creation Gate) → Architect/Engineer/QA/RedTeam → WasmCompiler → girt-runtime → tools/list_changed
  - Similarity layer wired in, real LLM in decision gates
  - Smoke test passing: celsius_to_fahrenheit end-to-end ~2.9s
  - Binary installed: ~/.cargo/bin/girt, config at ~/.config/girt/girt.toml
  - .mcp.json in repo root — ready for Claude Code integration test
  - cargo-component + wasm32-wasip1 installed on belthanior
  - 2026-02-22 session: massive pipeline improvement sprint
  - Planner agent added (triage-then-plan, ADR-012)
  - Continue-signal pattern: WASM ≤60s budget, return pending+resume_token, caller loops
  - Architect INPUT SPECIFICATION RULES: mechanical per-field checklist
  - Bug ticket severity tiers: Critical/High block, Medium/Low advisory
  - Circuit breaker: ask/proceed/fail policy (currently "proceed" = fail open)
  - Per-stage timing + token tracking throughout pipeline
  - Token budgets: Architect 100k, Planner 32k, QA/RedTeam 16k
  - cargo-component path made configurable (daemon PATH fix)
  - **First successful discord_approval WASM built**: 706KB cwasm artifact (2026-02-22 session)
  - **WASM HTTP fixed**: rebuilt with wasm32-wasip2 + wit-bindgen, proper WASI HTTP imports
  - **End-to-end approval flow tested**: Gate → Ask → WASM → Discord message posted (#girt-approvals, ID 1474968155850801185) → continue-signal loop working
  - **Tool Registry Sync**: tool_sync.rs committed; girt-tools repo bootstrap done locally; needs liamhelmer-bel collaborator access from Liam
  - **improve_tool pipeline**: EngineerAgent.improve() + Orchestrator.improve_tool() + build_loop_from_seed() committed; proxy endpoint not yet wired
  - WIT dep lesson: use directory per package, prepend `package wasi:http@0.2.6;` to types.wit/handler.wit, `impl Guest` (not nested path)
  - PR #7 open: https://github.com/Epiphytic/girt/pull/7
- **openclaw-voice** (active): Discord voice bot "Chip" for real-time voice conversations
  - Repo: ~/workspace/openclaw-voice, PR #3 on feat/voice-interaction-fixes
  - Services: LLM Qwen3-8B (:8000), STT whisper.cpp (:8001), TTS Kokoro (:8002), Speaker ID (:8003)
  - Config: /home/models/voice-bot.toml (outside repo)
  - Bot: bel-audio#8651, token at /home/models/discord-voice-token.txt
  - Gateway escalation working: Ed25519 device signing, agentId="main", cumulative streaming
  - **V2 architecture planned**: async ConversationLog + independent workers (STT, LLM, TTS, Escalation)
    - Design doc: plans/voice-bot-v2-architecture.md
    - Core issue: v1 pipeline cancellation loses tool/escalation results
  - Channel summary cron: every 5 min via crontab, uses Discord bot API + Qwen3-8B
  - Known issues: Qwen3-8B doesn't reliably call tools (needs fallback detection), farm noise hallucinations

## LinkedIn / Self-Marketing
- **Profile URL:** https://www.linkedin.com/in/liam-helmer/
- **Slug updated** from liam-helmer-devops → liam-helmer (2026-02-22)
- **Headline:** "Platform Engineer ♾️ I build AI systems that survive enterprise security reviews; where security is baked in, not bolted on."
- **About:** Rewritten 2026-02-22 — leads with enterprise AI gap, full-stack depth angle, organizational empathy
- **Content system:** Liam brain-dumps rough thoughts → Bel drafts → Liam tweaks → posts
- **Content pillars:** (1) What orgs get wrong with AI (2) How I think about X (3) Built/learned something
- **First post:** 2026-02-22 — "castles in the clouds" / agentic AI as language craft
  - URL: https://www.linkedin.com/feed/update/urn:li:activity:7431515159556169748/
- **Target cadence:** 2-3x/week (Tue/Thu optimal posting times)
- **Browser relay:** Working — port 18789, extension unpacked from /home/openclaw/openclaw/assets/chrome-extension
- **Image workflow:** Google AI Studio (aistudio.google.com) → generate → upload manually on desktop
- **Image upload limitation:** LinkedIn blocks programmatic file upload (React trusted event check) — must upload manually

## Local Model Services (belthanior)
- **Hardware:** AMD Radeon RX 7900 XTX (24GB VRAM + unified memory), ROCm
- **Management script:** `/home/models/vllm-server.py` — manages all three services
- **Config:** `/home/models/config.toml`
- **Weights:** `/home/models/weights/`
- **Logs:** `/home/models/logs/`
- **Eval harness:** `/home/models/eval.py` — 7-test tool-calling suite
- **Sudoers:** openclaw has NOPASSWD for vllm-server.py, apt-get
- **openclaw groups:** video, render (GPU access for non-root processes)

### LLM — Qwen2.5-32B-Instruct (port 8000)
- Runs in podman container (`kyuz0/vllm-therock-gfx1151:latest`)
- BF16, ~64GB, hermes tool parser
- 100% on tool-calling eval, 8.1s avg latency, very concise (167 tokens)
- `sudo /home/models/vllm-server.py start -d`

### STT — whisper-large-v3-turbo (port 8001)
- whisper.cpp with Vulkan GPU acceleration
- **12x realtime** (0.3s for 3.8s audio)
- Binary: `/home/models/whisper.cpp/build/bin/whisper-server`
- Endpoint: `/inference` (not OpenAI-compatible `/v1/audio/transcriptions`)
- `sudo /home/models/vllm-server.py stt start`

### TTS — kokoro-82m (port 8002)
- 82M param model, Apache licensed, CPU (fast enough at 5x realtime)
- Python venv at `/home/models/venv-tts/`
- OpenAI-compatible: `/v1/audio/speech`
- Voices: alloy, echo, fable, onyx, nova, shimmer (mapped to Kokoro voices)
- `python3 /home/models/vllm-server.py tts start`

### Model Eval Results (2026-02-24)
- **GLM-4.7-Flash:** 100% accuracy, 8.2s latency, verbose (461 tokens) — MoE, fast but chatty
- **Qwen2.5-72B-Instruct-AWQ:** Correct but 0.6 tok/s — **AWQ not accelerated on ROCm, avoid quantized models**
- **Qwen2.5-32B-Instruct:** 100% accuracy, 8.1s latency, concise (167 tokens) — **chosen as default**
- Key lesson: stick to BF16 unquantized models on this box, AWQ/GPTQ kernels don't accelerate on ROCm

### Speaker ID — Resemblyzer (port 8003)
- 256-dim voice embeddings, 11ms identification, Apache licensed
- Profiles stored in `/home/models/speaker-profiles/`
- Access tiers: full (Liam), standard (known household), basic (unknown)
- Enrollment: POST /enroll with audio + name, averages across multiple samples

### Wyoming Protocol Bridges (HA integration)
- STT bridge: port 10300, forwards to whisper.cpp, includes speaker ID
- TTS bridge: port 10200, forwards to Kokoro
- Transcript logging: `/home/models/logs/transcripts.jsonl` → Discord #voice-transcripts (1476027839391469718)

### Home Assistant
- Container on :8123 (podman, privileged, host network)
- Config: `/home/models/homeassistant/`, token in `.ha_token`
- Bluetooth built-in (hci0) — Govee sensors via BLE
- Liam's devices: Globe/CE lights (Tuya/WiFi), Arenti cameras ×4 (RTSP), Govee temp ×8 (BLE)
- WiFi mesh ~1.5 acres, 2 houses + outbuildings
- Replacing Google Home — wants local/private voice control + web search + calendar
- Plan: `plans/home-assistant.md`

### Discord Voice
- OpenClaw Discord bot is text-only — no voice gateway support
- Direct voice chat with Bel: web page or standalone Discord voice bot (not yet built)
- Voice wake supported on OpenClaw iOS/Android/Mac apps

## Liam's Farm
- 2 houses + outbuildings on ~1.5 acres
- WiFi mesh covers the property
- Uses Google Home extensively for light control across farm
- Wants privacy-first replacement with local AI
