#!/usr/bin/env bash
# Semantic memory search
# Usage: query.sh "natural language query" [limit=5] [--synthesize]
set -euo pipefail

DB="${AGENTDB_PATH:-$HOME/.openclaw/workspace/agentdb/memory.db}"
QUERY="${1:?Usage: query.sh <query> [limit] [--synthesize]}"
LIMIT="${2:-5}"
SYNTH="${3:-}"

ARGS=(--query "$QUERY" --k "$LIMIT" --format json --db "$DB")
[ "$SYNTH" = "--synthesize" ] && ARGS+=(--synthesize-context)

agentdb query "${ARGS[@]}" 2>&1
