# Voice Bot v2 Architecture — Async Conversation Log

**Status:** Draft  
**Date:** 2026-02-25  
**Author:** Bel  
**Context:** Current pipeline architecture loses context on cancellation, can't handle async tool results, and leaves users hanging. This redesign treats conversation as a shared append-only log with independent async workers.

## Problem Statement

The v1 architecture has a per-utterance pipeline (STT → LLM → TTS) that:
- Gets cancelled when new speech arrives, killing in-flight tool calls and escalations
- Maintains mutable per-pipeline history that diverges from reality when tasks are cancelled
- Can't fold async results (escalation responses, tool calls) back into conversation naturally
- Leaves users waiting with no feedback during long operations
- Processes background noise hallucinations ("Thank you") as full pipeline runs

## Core Principles

1. **Conversation log is the source of truth** — append-only, shared by all workers
2. **New speech cancels output, not work** — stop talking, but let LLM/tools finish
3. **Tool results arrive asynchronously** — they get appended to the log and inform the next turn
4. **Users are never left hanging** — keepalive messages when work is in progress

## Architecture

### Conversation Log

A thread-safe, append-only log per guild/voice session:

```python
@dataclass
class LogEntry:
    ts: float                    # monotonic timestamp
    kind: str                    # "user_speech" | "assistant" | "tool_result" | "escalation_result" | "system"
    speaker: str                 # user display name, bot name, tool name, agent name
    text: str                    # content
    meta: dict                   # extra data (stt_ms, llm_ms, tool_name, etc.)

class ConversationLog:
    """Append-only conversation log. Thread-safe."""
    
    def __init__(self):
        self._entries: list[LogEntry] = []
        self._lock = threading.Lock()
        self._version = 0        # increments on each append
        self._event = asyncio.Event()  # signaled on new entries
    
    def append(self, entry: LogEntry) -> int:
        """Append an entry, return new version."""
        with self._lock:
            self._entries.append(entry)
            self._version += 1
            self._event.set()
            self._event.clear()
            return self._version
    
    def snapshot(self) -> tuple[list[LogEntry], int]:
        """Return (entries, version) — safe to read without lock."""
        with self._lock:
            return list(self._entries), self._version
    
    def to_messages(self) -> list[dict]:
        """Convert log to OpenAI messages format for LLM context."""
        messages = []
        for entry in self._entries:
            if entry.kind == "user_speech":
                messages.append({"role": "user", "content": f"{entry.speaker}: {entry.text}"})
            elif entry.kind == "assistant":
                messages.append({"role": "assistant", "content": entry.text})
            elif entry.kind in ("tool_result", "escalation_result"):
                # Inject as system context so the LLM knows about async results
                messages.append({"role": "system", "content": f"[{entry.kind}] {entry.speaker}: {entry.text}"})
            elif entry.kind == "system":
                messages.append({"role": "system", "content": entry.text})
        return messages
```

### Workers

Four independent async workers, all reading from / writing to the conversation log:

#### 1. STT Worker
- Receives raw audio from VoiceSink (same debounce timer as now)
- Runs Whisper transcription
- Filters hallucinations (same list as now)
- On valid transcript: appends `user_speech` to log, signals LLM Worker
- **Does NOT get cancelled by anything**

#### 2. LLM Worker  
- Triggered when a new `user_speech` entry appears in the log
- Takes a **snapshot** of the full conversation log at trigger time
- Converts to messages, calls LLM with tools
- If LLM returns text: appends `assistant` to log, signals TTS Worker
- If LLM returns tool call: executes tool, appends `tool_result` to log, calls LLM again with updated context
- If LLM calls `escalate_to_bel`: spawns Escalation Worker, appends interim `assistant` response ("checking with Bel")
- **Key:** If a NEW `user_speech` arrives while LLM is running:
  - Let the current LLM call finish (don't waste the tokens)
  - But check log version after — if new speech arrived, **discard** the response (don't TTS it)
  - Re-trigger with the updated log that includes the new speech
- **Deduplication:** Only one LLM call active per user at a time. New triggers queue behind.

#### 3. TTS Worker
- Triggered when a new `assistant` entry appears in the log
- Synthesizes audio, queues for playback
- **Cancellable:** New `user_speech` cancels any in-progress TTS and clears the playback queue
- This is the ONLY thing that gets interrupted by new speech

#### 4. Escalation Worker
- Spawned by LLM Worker when `escalate_to_bel` is called
- Connects to gateway, sends request, waits for response
- Keepalive: every 20s, appends a `system` entry ("Bel is still thinking...")
  - TTS Worker picks this up and speaks it
- On response: appends `escalation_result` to log
- LLM Worker sees the new entry and generates a natural spoken response incorporating it
- **Never cancelled** — runs to completion or timeout (90s)

### Flow Diagram

```
Audio In → [VoiceSink + Debounce] → STT Worker → ConversationLog
                                                       ↕
                                                  LLM Worker → tool calls → Tool execution → Log
                                                       ↕               → escalation → Escalation Worker → Log
                                                  TTS Worker → Audio Out
                                                       ↑
                                              (cancelled by new speech)
```

### Cancellation Rules

| Event | STT | LLM | TTS | Escalation | Tools |
|-------|-----|-----|-----|-----------|-------|
| New speech arrives | ✅ continues | ✅ continues (discards stale response) | ❌ CANCELLED | ✅ continues | ✅ continues |
| User leaves voice | ❌ stops | ❌ stops | ❌ stops | ❌ stops | ❌ stops |

### Handling Background Noise ("Thank you" problem)

The current hallucination filter catches known phrases. Additional improvements:

1. **Energy gate BEFORE Whisper** — if RMS energy of the audio is below threshold, skip STT entirely. This avoids burning Whisper cycles on silence/ambient noise.
2. **Minimum audio duration** — already have MIN_UTTERANCE_MS=800, may need to bump to 1000ms
3. **Rate limit STT** — if we've filtered 3+ hallucinations in a row, increase the debounce timer temporarily (adaptive silence detection)
4. **Don't clear accumulated audio on hallucination** — only clear on valid speech

### Handling "What's in this channel?" Questions

Two improvements:

1. **Channel summary in system prompt** — already done, but summaries need to exclude bot's own messages
2. **Smart escalation** — when the LLM doesn't have enough context to answer a channel question, it should escalate with the specific channel ID so Bel can `message(action=read)` to get real messages

### State Management

```python
class VoiceSession:
    """Per-guild voice session state."""
    
    log: ConversationLog
    system_prompt: str           # includes channel context
    
    # Worker state
    stt_task: asyncio.Task | None
    llm_task: asyncio.Task | None  
    tts_task: asyncio.Task | None
    escalation_tasks: dict[str, asyncio.Task]  # keyed by request ID
    
    # Playback
    playback_queue: asyncio.Queue[bytes]
    tts_cancel: asyncio.Event    # set to cancel current TTS
    
    # LLM state
    pending_llm_trigger: bool    # new speech arrived while LLM was busy
    last_llm_version: int        # log version when LLM last ran
```

### Message Format for LLM

The system prompt + conversation log becomes:

```
[system] You are Chip, a voice assistant... (base prompt)
[system] Channel context: #models-and-usage on GIRT workspace... (channel summary)
[user] Liam: Hey Chip, what's Bel working on?
[assistant] I'm checking with Bel on that, one moment!
[system] [escalation_result] Bel: Bel is currently on standby, monitoring LinkedIn engagement...
[user] Liam: What about the weather?
```

This way the LLM naturally sees the full conversation including async results.

## Implementation Plan

### Phase 1: ConversationLog + Refactored Workers (core)
1. Create `ConversationLog` class
2. Create `VoiceSession` to hold per-guild state
3. Refactor STT to write to log instead of queue
4. Refactor LLM worker to read from log snapshots
5. Refactor TTS worker with proper cancellation
6. Wire up the trigger chain (log events → worker signals)

### Phase 2: Async Tool Calls + Escalation
7. Refactor escalation as independent worker writing to log
8. Add keepalive messages during escalation
9. LLM worker re-triggers when escalation_result appears

### Phase 3: Noise Reduction
10. Add RMS energy gate before STT
11. Adaptive debounce after hallucination streaks
12. Filter bot's own messages from channel summaries

### Phase 4: Polish
13. Conversation log truncation (keep last N entries for context window)
14. Transcript posting from log (not inline)
15. Graceful session cleanup

## Migration

- Keep VoiceSink + debounce timer as-is (they work)
- Replace `_process_utterances` dispatcher with new worker architecture  
- Keep gateway_client as-is (it works now)
- Keep tools.py as-is
- Pipeline config stays the same

## Open Questions

1. **Log persistence** — should conversation logs survive bot restarts? (Probably not for v1)
2. **Multi-user** — current design is per-guild. Multiple users talking simultaneously need per-user LLM workers but shared log. Defer for now.
3. **Context window management** — with tools and escalations, the log could get long. Need a truncation strategy (sliding window of last N turns).
4. **Streaming LLM → TTS** — v2 could stream LLM tokens to TTS for lower latency. Complex but big win. Defer to v3.
