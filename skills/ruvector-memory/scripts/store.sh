#!/usr/bin/env bash
# Store a memory episode into AgentDB
# Usage: store.sh "text" "source-file" "tag1,tag2" [reward 0.0-1.0]
set -euo pipefail

DB="${AGENTDB_PATH:-$HOME/.openclaw/workspace/agentdb/memory.db}"
SESSION="memory-$(date +%s)"
TEXT="${1:?Usage: store.sh <text> [source] [tags] [reward]}"
SOURCE="${2:-manual}"
TAGS="${3:-memory}"
REWARD="${4:-0.8}"

agentdb reflexion store \
  "$SESSION" \
  "$TEXT" \
  "$REWARD" \
  true \
  "source:$SOURCE tags:$TAGS" \
  --db "$DB" 2>&1 || \
agentdb reflexion store "$SESSION" "$TEXT" "$REWARD" true "source:$SOURCE tags:$TAGS" "$DB" 2>&1

echo "✅ Stored: ${TEXT:0:80}..."
