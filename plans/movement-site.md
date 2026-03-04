# Movement Practice Site — Plan

## Overview
A GitHub Pages site hosted at `epiphytic.github.io/movement-practice` (or similar) that serves as a daily movement practice guide. Multi-user architecture (starting with Liam), per-day pages with exercise details, section timers, and TTS audio. Daily Discord reminders.

## Architecture

### Repo & Hosting
- **Repo:** `Epiphytic/movement-practice` (public)
- **Hosting:** GitHub Pages from `main` branch, `/docs` folder (or root)
- **Stack:** Static HTML/CSS/JS — no build step, no framework. Keep it simple.
- **Why no framework:** It's a small content site. Vanilla JS + CSS grid is enough. Easy to maintain, zero build dependencies.

### Site Structure
```
/
├── index.html              # Landing page — what this is, list of users
├── css/
│   └── style.css           # Shared styles
├── js/
│   ├── timer.js            # Stoppable countdown timer component
│   └── audio.js            # TTS audio playback (pre-generated files)
├── audio/                  # Pre-generated TTS .mp3 files
│   └── liam/
│       ├── monday-section-1.mp3
│       └── ...
├── exercises/              # Shared exercise detail pages
│   ├── founder.html
│   ├── cars-full-body.html
│   ├── anchored-back-extension.html
│   ├── woodpecker.html
│   ├── atg-split-squat.html
│   ├── tibialis-raise.html
│   ├── 90-90-hip-switch.html
│   ├── cossack-squat.html
│   ├── deep-squat-hold.html
│   ├── wall-slide.html
│   ├── dead-hang.html
│   ├── push-up.html
│   ├── crocodile-breathing.html
│   ├── lunge-decompression.html
│   ├── integrated-hinge.html
│   ├── hip-cars.html
│   └── single-leg-calf-raise.html
└── liam/
    ├── index.html          # Liam's weekly overview
    ├── monday.html
    ├── tuesday.html
    ├── wednesday.html
    ├── thursday.html
    ├── friday.html
    ├── saturday.html
    └── sunday.html
```

### Exercise Detail Pages (`/exercises/`)
Each exercise gets its own page with:
- Name, description, muscles targeted
- Step-by-step form cues
- Common mistakes
- Embedded YouTube video (where available) or written walkthrough
- Progression/regression options
- Why it's in the program

These are **shared across users** — Liam's day pages link into them.

### Day Pages (`/liam/{day}.html`)
Each day page contains:
- **Morning Foundation** section (same every day)
- **Daily Add-On** section (varies by day)
- Each exercise block has:
  - Exercise name (linked to detail page)
  - Sets × reps or hold duration
  - **Timer button** — click to start countdown, click again to pause, auto-advances or resets
  - **Audio icon** 🔊 — plays pre-generated TTS narration for that section
- Visual progress indicator (which section you're on)
- Mobile-first responsive design (he'll use this on his phone in the morning)

### Timer Component
- Countdown timer per section (e.g., "Founder Hold — 45 seconds")
- States: ready → running → paused → done
- Visual: large numbers, color change (green → yellow → red)
- Audio chime on completion (short beep, not annoying)
- For rep-based exercises: simple "Mark Complete" button instead of timer
- No auto-advance between exercises (let the user control pace)

### TTS Audio Generation
- **Generated at build time** using local Kokoro TTS (port 8002)
- Script: `generate-audio.sh` — reads exercise descriptions and day narrations, calls Kokoro API, saves .mp3 files to `/audio/`
- Each section gets a narration like: "Founder hold. Stand with feet hip-width apart. Hinge at the hips, reach your arms forward and up. Hold for 45 seconds. Focus on driving weight through your heels and engaging your posterior chain."
- Re-run the script when content changes
- Audio files committed to repo (small, Kokoro produces compact files)

### Daily Discord Reminder
- **OpenClaw cron job** — runs daily at 6:30 AM Pacific
- Sends to channel `1475048256655327392`
- Message format:
  ```
  🏋️ Good morning! Here's your movement practice for today:
  https://epiphytic.github.io/movement-practice/liam/monday.html
  ```
- Day is determined dynamically
- Cron expression: `30 6 * * * America/Vancouver`

## Design Notes
- **Mobile-first** — big tap targets, large text, works in portrait
- **Dark mode** by default (early morning use)
- **Minimal** — no animations, no loading spinners, no bloat
- **Offline-capable** — consider a simple service worker so it works without signal on the farm (stretch goal)

## Implementation Phases

### Phase 1: Core Site (this PR)
- [ ] Create repo, set up GitHub Pages
- [ ] Landing page + CSS
- [ ] All 7 day pages for Liam with exercise content
- [ ] Exercise detail pages (all ~17 exercises)
- [ ] Timer component
- [ ] Audio playback UI (placeholder — no audio files yet)
- [ ] Mobile responsive

### Phase 2: Audio + Reminders (follow-up)
- [ ] Generate TTS audio files with Kokoro
- [ ] Wire audio playback to generated files
- [ ] Set up Discord cron reminder

### Phase 3: Polish (future)
- [ ] Service worker for offline
- [ ] Progress tracking (localStorage)
- [ ] Weekly review/stats page
- [ ] Add more users

## Questions for Liam
1. Repo name preference? `movement-practice`, `daily-movement`, `movement-lab`?
2. Any color/brand preferences for the site?
3. The cron reminder — 6:30 AM work, or different time?
4. Want the reminder to include the exercise list inline, or just the link?

## Ready to Build
Once plan is approved, I'll spawn a sub-agent to build Phase 1 and open a PR.
