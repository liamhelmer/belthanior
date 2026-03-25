#!/usr/bin/env bash
# Store a memory into the vector index
# Usage: store.sh "text" "source-file" "tag1,tag2"
set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
AGENTDB_DIR="$WORKSPACE/agentdb"

TEXT="${1:?Usage: store.sh <text> [source] [tags]}"
SOURCE="${2:-manual}"
TAGS="${3:-}"

cd "$AGENTDB_DIR"

# Build metadata JSON
META="{\"source\":\"$SOURCE\",\"tags\":\"$TAGS\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

npx agentdb store \
  --dir "$AGENTDB_DIR" \
  --text "$TEXT" \
  --metadata "$META" 2>&1

echo "Stored: ${TEXT:0:80}..."
