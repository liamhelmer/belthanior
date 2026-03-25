---
name: memory-audit
description: Weekly memory audit skill. Generates a structured report from recent daily notes and channel memories, identifying gaps in MEMORY.md, stale channel files, recurring mistakes, missing facts, and rule improvements. Use when asked to run a memory audit, generate a weekly memory report, or review memory health. Runs automatically every Sunday at 9am Pacific — reads everything since the last audit timestamp, generates a report saved to memory/MEMORY-AUDIT-PROPOSAL.md, then messages Liam in #mxdx-general (1486277862217613323) with a summary and link.
---

# Memory Audit Skill

Generates a weekly memory health report and messages Liam with findings.

## State File

Audit state is stored in `memory/memory-audit-state.json`:
```json
{
  "last_audit_ts": "2026-03-25T08:20:00Z",
  "last_report_path": "memory/MEMORY-AUDIT-PROPOSAL.md"
}
```

## Workflow

### 1. Load state
Read `memory/memory-audit-state.json` to get `last_audit_ts`.

### 2. Gather source material
- All `memory/YYYY-MM-DD.md` files with mtime or content newer than `last_audit_ts`
- All `memory/discord-*.md` channel files
- `MEMORY.md`, `AGENTS.md`, `SOUL.md`
- Today's date for context

### 3. Generate the report
Analyse the gathered material for:

**A. MEMORY.md gaps** — Facts in daily notes not in MEMORY.md (infrastructure changes, new projects, config updates, social/publishing events, operational lessons). For each: state the fact, its source file, and where in MEMORY.md it should go.

**B. Stale channel memory files** — Files not updated since `last_audit_ts` that had activity. List what's missing.

**C. Recurring mistakes / rule violations** — Patterns of the same mistake across multiple sessions. Quote evidence. Propose concrete AGENTS.md amendment text.

**D. AGENTS.md improvements** — Rules that are unclear, missing, or weakly enforced based on observed failures.

**E. SOUL.md** — Only flag if a genuine personality/behaviour gap is observed. Usually no changes needed.

**F. Overall health score** — Brief A/B/C/D per category: daily notes, MEMORY.md, channel files, AGENTS.md.

Format: markdown with clear `##` sections. Keep actionable — every finding should have a proposed fix.

### 4. Save the report
Write to `memory/MEMORY-AUDIT-PROPOSAL.md` (overwrite previous).

### 5. Update state file
```json
{
  "last_audit_ts": "<current ISO timestamp>",
  "last_report_path": "memory/MEMORY-AUDIT-PROPOSAL.md"
}
```

### 6. Message Liam
Send to Discord channel **1486277862217613323** (#mxdx-general):

```
Weekly memory audit complete 🧠

Report: https://github.com/liamhelmer/belthanior/blob/main/memory/MEMORY-AUDIT-PROPOSAL.md

Top findings:
• [2-3 bullet summary of most important gaps/issues]

Reply "implement audit" to apply all recommendations.
```

Then push to git:
```bash
cd /home/openclaw/.openclaw/workspace
git add memory/MEMORY-AUDIT-PROPOSAL.md memory/memory-audit-state.json
git commit -m "chore(memory): weekly audit $(date +%Y-%m-%d)"
git push origin main
```

## Implementation Notes

- Do NOT implement the report findings automatically — generate the report and wait for Liam's approval
- If `memory-audit-state.json` doesn't exist, use `2026-03-25T08:20:00Z` as the initial `last_audit_ts`
- When Liam says "implement audit" or approves the findings, apply them directly (editing MEMORY.md, AGENTS.md, channel files as needed), then push and confirm
