# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## Sudo Access (NOPASSWD)

openclaw has passwordless sudo for:
- `/usr/bin/apt-get` — package installs
- `/usr/bin/apt` — package management
- `/usr/bin/snap` — snap packages
- `/usr/bin/podman image prune -f` — prune dangling podman images
- `/home/models/vllm-server.py` — model service management (start/stop/pull/model-prune)
- `/home/models/rocm-maintenance.sh` — ROCm GPU maintenance

Use `sudo /home/models/vllm-server.py model-prune <fragment>` to delete model weights.
Use `sudo podman image prune -f` to clean dangling container layers.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

Add whatever helps you do your job. This is your cheat sheet.
