# Claude Code Autonomy Skill

## Rules

### Auto-respond to Claude Code questions when:
- Question is about implementation details, naming, file structure
- Question is about which test to write or how to format something
- Question is asking for confirmation on a straightforward change
- Question is about dependency versions or tooling choices

### Forward to user (👋) when:
- Architecture decisions that change project direction
- Destructive operations (deleting repos, dropping databases, removing files outside workspace)
- Ambiguous requirements where multiple valid interpretations exist
- Security-sensitive changes (auth, tokens, permissions)
- Anything that would be sent externally (emails, posts, messages to other people)

### Notification Formats

👋 [session-name] Important question — needs your decision:
> "question text"

🤖 [session-name] finished:
Summary of what was done, files changed, any issues found.

### Default Behavior
- Auto-respond to routine questions
- Let Claude Code run with full permissions (bypassPermissions)
- Timeout: 1800s (30 min) for coding tasks
- Summarize results when sessions complete
