#!/usr/bin/env bash
# Check AgentDB index status
set -euo pipefail

DB="${AGENTDB_PATH:-$HOME/.openclaw/workspace/agentdb/memory.db}"

if [ ! -f "$DB" ]; then
  echo "STATUS: NOT INITIALIZED — run scripts/setup.sh"
  exit 1
fi

agentdb status --db "$DB" --verbose 2>&1
agentdb db stats --db "$DB" 2>/dev/null || true
