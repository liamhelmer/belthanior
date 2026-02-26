# Voice Agent Architecture

## Overview
The Discord voice bot is its own agent with a fast local LLM (Qwen3-8B) for immediate conversational responses. For tasks beyond its scope, it escalates to the main OpenClaw agent (Bel) via `sessions_send`.

## Two-Tier Response Model

### Tier 1: Direct Response (voice bot handles itself)
- Greetings, small talk, conversation
- Simple factual questions
- Time, date, basic math
- Anything the local LLM can confidently answer
- **Latency target**: <4s total (STT + LLM + TTS)

### Tier 2: Escalation to Main Agent (Bel)
- Tool use (email, calendar, lights, search)
- Tasks requiring memory/context from main agent
- Complex multi-step requests
- Anything the voice bot is uncertain about

### Escalation Flow
1. Voice bot receives transcription
2. Local LLM decides: handle directly or escalate?
3. If escalating:
   a. Immediately respond to user: "Let me check with Bel" / "I'll ask Bel to do that"
   b. Send request to main agent via `sessions_send`
   c. Poll/wait for response with progress updates every ~30s
      - "Bel is thinking about that..."
      - "Bel is using some tools, hang on..."  
      - "Still waiting on Bel..."
   d. On response: TTS the result back to the user
   e. On timeout (5 min): "Sorry, I can't reach Bel right now"

## Implementation Notes

### Escalation Detection
The local LLM system prompt should include instructions like:
```
If the user asks you to do something that requires tools, memory, or actions
beyond conversation (email, calendar, lights, search, file operations, etc.),
respond ONLY with: [ESCALATE] <description of what to do>
```

The voice pipeline detects `[ESCALATE]` prefix and routes to main agent.

### Communication with Main Agent
- Use `sessions_send(sessionKey, message)` to reach Bel
- Include context: who's asking, what they said, voice channel info
- Main agent responds via the same session mechanism

### Progress Tracking
- After sending to main agent, start a background task
- Every 30s, TTS a progress message
- If main agent sends partial updates, relay those
- 5-minute hard timeout

## Services
- **LLM**: Qwen3-8B on localhost:8000 (15GB VRAM, fast inference)
- **STT**: whisper.cpp on localhost:8001 (Vulkan GPU, 12x realtime)
- **TTS**: Kokoro on localhost:8002 (5x realtime)
- **Speaker ID**: Resemblyzer on localhost:8003

## Status
- [x] Basic voice pipeline working (STT → LLM → TTS → Discord)
- [x] VAD with RMS energy gate for background noise
- [x] Transcript posting to Discord channel
- [x] Mute detection for end-of-utterance
- [ ] Escalation to main agent
- [ ] Progress polling loop
- [ ] Escalation detection in LLM prompt
- [ ] Post transcripts to originating channel (not separate #voice-transcripts)
