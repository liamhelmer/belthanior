#!/usr/bin/env bash
# Semantic memory search
# Usage: query.sh "natural language query" [limit=5]
set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
AGENTDB_DIR="$WORKSPACE/agentdb"

QUERY="${1:?Usage: query.sh <query> [limit]}"
LIMIT="${2:-5}"

cd "$AGENTDB_DIR"

npx agentdb search \
  --dir "$AGENTDB_DIR" \
  --query "$QUERY" \
  --limit "$LIMIT" 2>&1
