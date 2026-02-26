# Home Assistant Setup Plan — belthanior

## Goal
Replace Google Home with a fully local, private voice assistant + home automation hub. No data leaves the property. Custom voice commands including web search, personal queries, and farm management — powered by our local AI stack.

## Existing Hardware
- **Plugs & Lights:** Mostly Globe (Tuya-based), some CE (also likely Tuya)
- **Cameras:** 4× Arenti (WiFi, RTSP capable)
- **Temp Sensors:** ~8× Govee (BLE)
- **Network:** WiFi mesh covering ~1.5 acres (2 houses + outbuildings)
- **Compute:** belthanior with 7900 XTX GPU, local LLM/STT/TTS already running
- **Voice:** Google Home (to be replaced/supplemented)

## Architecture

```
Voice Satellite / Phone / Browser
         │ wake word
         ▼
┌─────────────────────────────────────────────────────┐
│  Home Assistant (:8123)                              │
│                                                      │
│  Assist Pipeline:                                    │
│    STT ──→ whisper.cpp (:8001, Vulkan GPU, 12x RT)  │
│    LLM ──→ Qwen2.5-32B (:8000, GPU)                │
│    TTS ──→ Kokoro (:8002, CPU, 5x RT)               │
│                                                      │
│  The LLM can:                                        │
│    • Control lights, plugs, sensors (HA actions)     │
│    • Search the web (custom tool)                    │
│    • Query Bel/OpenClaw (custom tool)                │
│    • Answer general knowledge questions              │
│    • Run custom commands you define                  │
│                                                      │
│  Integrations:                                       │
│    • Tuya (Globe/CE plugs & lights, local)           │
│    • Govee BLE (temp sensors via Bluetooth)          │
│    • Arenti/RTSP (cameras)                           │
│    • Wyoming (STT/TTS bridge)                        │
│    • OpenAI Conversation (→ local Qwen)              │
└─────────────────────────────────────────────────────┘
```

## Phase 1: Core Install

### 1a. Home Assistant Container
```bash
sudo podman run -d \
  --name homeassistant \
  --restart=always \
  --privileged \
  --network=host \
  -v /home/models/homeassistant:/config \
  -v /etc/localtime:/etc/localtime:ro \
  ghcr.io/home-assistant/home-assistant:stable
```
- Web UI: `http://belthanior:8123`
- `--privileged` + `--network=host` for Bluetooth (Govee) and mDNS (device discovery)
- Add to vllm-server.py as `ha` subcommand

### 1b. Bluetooth for Govee
belthanior needs a Bluetooth adapter if it doesn't have one built-in:
```bash
# Check
hciconfig
# or
bluetoothctl show
```
- If no BT: USB Bluetooth 5.0 dongle (~$10)
- Govee sensors broadcast BLE — HA picks them up automatically via Govee BLE integration
- Range: ~30m per sensor, should cover both houses if belthanior is central

### 1c. Initial Device Setup
1. **Tuya integration** for Globe/CE devices:
   - Install Tuya Smart or Smart Life app (if not already)
   - Add integration in HA → scan QR code from app
   - All plugs/lights appear automatically
   - **Local Tuya (HACS):** For fully local control without Tuya cloud, install the LocalTuya custom integration — extracts device keys and talks directly to devices over WiFi
2. **Govee BLE** integration — auto-discovers sensors
3. **Generic Camera** integration for Arenti cameras (RTSP streams)

## Phase 2: Wire Local AI

### 2a. LLM as Conversation Agent
HA Settings → Integrations → OpenAI Conversation:
- **Base URL:** `http://localhost:8000/v1`
- **API Key:** `sk-not-needed` (any string)
- **Model:** `Qwen/Qwen2.5-32B-Instruct`

This makes Qwen the brain of Assist. It gets access to all exposed entities and can control them via natural language.

### 2b. Wyoming Protocol Wrappers
HA uses the Wyoming protocol to discover STT/TTS services. We need lightweight bridges:

**whisper-wyoming-bridge** (STT):
```python
# Accepts Wyoming audio stream → forwards to whisper.cpp :8001/inference
# Runs on port 10300
```

**kokoro-wyoming-bridge** (TTS):
```python
# Accepts Wyoming TTS request → calls Kokoro :8002/v1/audio/speech
# Runs on port 10200
```

Add as `wyoming-stt` and `wyoming-tts` subcommands to the management script.

### 2c. Assist Pipeline
Settings → Voice Assistants → New Pipeline:
- **Name:** "Local Assistant"
- **Language:** English
- **STT:** Wyoming Whisper
- **Conversation:** OpenAI (local Qwen)
- **TTS:** Wyoming Kokoro
- **Wake word:** openWakeWord (optional)

## Phase 3: Custom Voice Commands (The Good Stuff)

This is where it gets better than Google Home. The LLM conversation agent can be given custom tools via HA's intent system + our own extensions.

### 3a. Web Search from Voice
"Hey assistant, search for when to plant garlic on Vancouver Island"

The OpenAI Conversation integration supports **custom tools**. We add a web search tool that the LLM can call:

```yaml
# configuration.yaml
intent_script:
  web_search:
    action:
      - service: rest_command.web_search
        data:
          query: "{{ query }}"
      - service: tts.speak
        data:
          message: "{{ result }}"

rest_command:
  web_search:
    url: "http://localhost:XXXXX/search?q={{ query }}"
    method: GET
```

Or better — give the LLM a custom tool definition in its system prompt that calls our Brave Search API (once configured) or a local SearXNG instance.

### 3b. SearXNG (Private Search Engine)
Run a local SearXNG instance — privacy-respecting metasearch engine:
```bash
sudo podman run -d \
  --name searxng \
  --restart=always \
  -p 8888:8080 \
  -v /home/models/searxng:/etc/searxng \
  searxng/searxng
```
- No API keys needed
- Aggregates Google, Bing, DuckDuckGo results
- The LLM calls it as a tool when you ask a search question
- "What's the weather tomorrow?" → LLM → SearXNG → spoken answer

### 3c. Custom Commands via Bel
"Hey assistant, ask Bel to check my email"
"Hey assistant, what's on my calendar today?"

Route complex queries through OpenClaw/Bel via REST:
```yaml
rest_command:
  ask_bel:
    url: "http://localhost:OPENCLAW_PORT/api/query"
    method: POST
    payload: '{"message": "{{ query }}"}'
```

### 3d. Other Custom Commands
- "What temperature is the barn?" → direct Govee sensor query
- "Show me the front camera" → cast Arenti RTSP to a display
- "Set a timer for 20 minutes" → local, no Google
- "Add eggs to the shopping list" → HA shopping list
- "Play music in the kitchen" → Sonos integration (we have the skill)
- "Lock down the property" → custom scene: all exterior lights on, cameras recording, notification sent

## Phase 4: Cameras (Arenti)

### RTSP Setup
Most Arenti cameras support RTSP. Check the app for stream URLs (usually `rtsp://IP:554/stream1`).

```yaml
# configuration.yaml
camera:
  - platform: generic
    name: Front Door
    stream_source: rtsp://admin:password@192.168.x.x:554/stream1
    still_image_url: http://192.168.x.x/snapshot.jpg
```

### Optional: Frigate NVR
For AI-powered object detection (person, car, animal on the driveway):
- Run Frigate container with the 7900 XTX for detection
- Get alerts: "Person detected at barn door"
- Record clips only when motion/objects detected (saves storage)

## Phase 5: Speaker Recognition + Access Control

### Why
"Hey assistant, what's on my calendar?" should work for Liam but not for guests. Voice ID determines who's speaking and gates access to personal data.

### Architecture
```
Audio → whisper.cpp (transcribe) ──→ text
  └──→ Speaker ID (embedding)  ──→ identity
                                        │
                                        ▼
                              ┌─────────────────┐
                              │ Access Control   │
                              │                  │
                              │ Liam: full       │
                              │  - calendar      │
                              │  - email         │
                              │  - web search    │
                              │  - Bel queries   │
                              │  - all devices   │
                              │                  │
                              │ Known: standard  │
                              │  - lights/plugs  │
                              │  - temp queries  │
                              │  - timers        │
                              │                  │
                              │ Unknown: basic   │
                              │  - lights only   │
                              └─────────────────┘
```

### Model: Resemblyzer (recommended)
- **256-dim voice embeddings** via deep learning encoder
- Pure Python, ~50MB model, runs on CPU in <100ms
- Cosine similarity for matching — simple threshold
- Enrollment: record 3-5 utterances per person → store average embedding
- Already in venv-stt or new lightweight venv
- License: Apache 2.0

**Alternative:** SpeechBrain ECAPA-TDNN (0.8% EER, state-of-art accuracy but heavier — torch dependency). Resemblyzer is good enough for household-scale identification.

### How it works
1. Audio arrives at the voice pipeline
2. **Parallel processing:**
   - whisper.cpp transcribes the speech → text
   - Resemblyzer extracts speaker embedding → 256-dim vector
3. Compare embedding against enrolled speakers (cosine distance)
4. If distance < 0.75 → identified as that speaker
5. Speaker identity injected into LLM system prompt:
   - "The current speaker is Liam (full access)" → LLM can call calendar, email, search tools
   - "The current speaker is unknown (basic access)" → LLM limited to device control

### Enrollment Flow
Via HA UI or voice command:
1. "Hey assistant, enroll my voice"
2. System asks for 3 phrases: "Read this sentence..." 
3. Extracts embeddings, averages them, stores as profile
4. Links profile to HA user (for permissions)

### Integration Point
A thin middleware between whisper.cpp and the LLM conversation agent:
```python
# speaker-id-server.py on port 8003
# POST /identify with audio → returns {speaker: "liam", confidence: 0.92}
# Called by the Wyoming STT wrapper before forwarding to LLM
```

### Phone Access (Option C supplement)
- HA Companion app authenticates via HA user login
- No voice ID needed — the app knows who you are
- Full access on your phone, basic access on shared satellites

## Phase 6: Replace Google Home

### Voice Satellites
Instead of Google Home, use dedicated hardware running ESPHome:
- **ESP32-S3-BOX-3** (~$45) — built-in mic, speaker, screen
- **M5Stack Atom Echo** (~$13) — tiny mic+speaker, wall-mountable
- Both connect to HA via ESPHome, use our local pipeline

### Phone App
- HA Companion app (iOS/Android) has built-in Assist
- Uses the same local pipeline — tap mic, speak, get response
- Works on WiFi anywhere on the property

### Transition Plan
1. Install HA + local voice first
2. Run parallel with Google Home for a week
3. Move automations over one by one
4. Disconnect Google Home when comfortable

## Shopping List

### Immediate (get started, ~$10-25)
- [ ] USB Bluetooth 5.0 dongle (if belthanior lacks BT) — ~$10
- [ ] Nothing else — all existing devices should integrate

### Phase 2 (~$50-100)
- [ ] ESP32-S3-BOX-3 voice satellite ×1 (kitchen?) — ~$45
- [ ] M5Stack Atom Echo ×1-2 (other rooms) — ~$13 each

### Phase 3 (nice to have)
- [ ] Zigbee dongle (for future Zigbee devices, more reliable than WiFi) — ~$15
- [ ] Additional sensors as needed

## Why This Is Better Than Google Home
1. **Privacy:** All processing local. Voice, queries, device data — nothing leaves belthanior
2. **Custom commands:** Web search, email check, calendar, Bel queries — Google can't do this
3. **No subscriptions:** Zero ongoing cost
4. **Smarter:** Qwen2.5-32B is a real LLM, not a pattern matcher. It understands context
5. **Extensible:** Add any automation, any device, any custom skill
6. **Reliable:** Works when internet is down (important on a farm)
7. **Your data:** Temperature history, usage patterns, camera feeds — all yours, not Google's
